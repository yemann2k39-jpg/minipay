import {
  BadRequestException,
  ConflictException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { createHash, randomBytes } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { LedgerAccountKind } from '@prisma/client';
import { generateMerchantCode } from '../merchant-api/merchant-api.service';
import { RegisterDto } from './dto/register.dto';
import { RegisterBusinessDto } from './dto/register-business.dto';
import { LoginDto } from './dto/login.dto';

const ACCESS_TTL = '15m';
const REFRESH_TTL_DAYS = 30;

@Injectable()
export class AuthService {
  constructor(
    private prisma: PrismaService,
    private jwt: JwtService,
  ) {}

  async register(dto: RegisterDto) {
    const existing = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (existing) throw new ConflictException('An account with this email already exists');

    const passwordHash = await bcrypt.hash(dto.password, 12);
    const user = await this.prisma.user.create({
      data: {
        email: dto.email,
        displayName: dto.displayName,
        phone: dto.phone,
        passwordHash,
      },
    });
    return this.issueTokens(user.id, user.email);
  }

  /**
   * Register a business (PGW-17): one transaction creates the owner User
   * (role MERCHANT), its MERCHANT settlement ledger account, and the Merchant
   * row. No API key yet — the owner creates/rotates one from the app.
   */
  async registerBusiness(dto: RegisterBusinessDto) {
    const existing = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (existing) throw new ConflictException('An account with this email already exists');

    const passwordHash = await bcrypt.hash(dto.password, 12);
    const result = await this.prisma.$transaction(async (tx) => {
      const user = await tx.user.create({
        data: {
          email: dto.email,
          displayName: dto.displayName,
          phone: dto.phone,
          passwordHash,
          role: 'MERCHANT',
        },
      });
      const account = await tx.ledgerAccount.create({
        data: {
          kind: LedgerAccountKind.MERCHANT,
          currency: 'SGD',
          ownerId: user.id,
        },
      });
      let merchant = null;
      for (let i = 0; i < 5 && !merchant; i++) {
        try {
          merchant = await tx.merchant.create({
            data: {
              code: generateMerchantCode(),
              name: dto.businessName.trim(),
              ledgerAccountId: account.id,
              ownerUserId: user.id,
            },
          });
        } catch (e: any) {
          if (e?.code !== 'P2002') throw e;
        }
      }
      if (!merchant) throw new ConflictException('Could not generate a unique merchant code');
      return { user, merchant };
    });
    const tokens = await this.issueTokens(result.user.id, result.user.email);
    return { ...tokens, merchant: { code: result.merchant.code, name: result.merchant.name } };
  }

  async login(dto: LoginDto) {
    const user = await this.prisma.user.findUnique({ where: { email: dto.email } });
    // Same error for unknown email / wrong password (no account enumeration).
    if (!user || !(await bcrypt.compare(dto.password, user.passwordHash))) {
      throw new UnauthorizedException('Invalid email or password');
    }
    // FROZEN accounts can still log in (read-only: balance + history) —
    // money-movement endpoints reject them individually. CLOSED cannot.
    if (user.status === 'CLOSED') {
      throw new UnauthorizedException('This account is closed');
    }
    return this.issueTokens(user.id, user.email, user.pinHash !== null);
  }

  async refresh(refreshToken: string) {
    let payload: { sub: string; email: string };
    try {
      payload = await this.jwt.verifyAsync(refreshToken, { secret: process.env.JWT_REFRESH_SECRET });
    } catch {
      throw new UnauthorizedException('Invalid or expired session');
    }
    const tokenHash = this.hashToken(refreshToken);
    const stored = await this.prisma.refreshToken.findUnique({ where: { tokenHash } });
    if (!stored || stored.revokedAt || stored.expiresAt < new Date()) {
      throw new UnauthorizedException('Invalid or expired session');
    }
    // Rotate: revoke old, issue new pair.
    await this.prisma.refreshToken.update({
      where: { id: stored.id },
      data: { revokedAt: new Date() },
    });
    return this.issueTokens(payload.sub, payload.email);
  }

  async logout(refreshToken: string) {
    const tokenHash = this.hashToken(refreshToken);
    await this.prisma.refreshToken.updateMany({
      where: { tokenHash, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    return { success: true };
  }

  async setupPin(userId: string, pin: string) {
    if (!/^\d{6}$/.test(pin)) throw new BadRequestException('PIN must be exactly 6 digits');
    const pinHash = await bcrypt.hash(pin, 12);
    await this.prisma.user.update({ where: { id: userId }, data: { pinHash } });
    return { success: true };
  }

  async hasPin(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { pinHash: true },
    });
    return { hasPin: user?.pinHash != null };
  }

  /** Profile of the logged-in user (PGW-7: creation date bounds the history UI). */
  async me(userId: string, email: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        displayName: true,
        phone: true,
        role: true,
        status: true,
        createdAt: true,
      },
    });
    return { ...user, email };
  }

  /** Verify a payment PIN. 401 is reserved for session/auth failures —
   *  a wrong PIN is a business rejection (400), not an authentication failure. */
  async verifyPin(userId: string, pin: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user?.pinHash) throw new BadRequestException('No payment PIN set up');
    if (!(await bcrypt.compare(pin, user.pinHash))) {
      throw new BadRequestException('Incorrect PIN');
    }
    return { success: true };
  }

  private hashToken(token: string) {
    return createHash('sha256').update(token).digest('hex');
  }

  private async issueTokens(userId: string, email: string, hasPin?: boolean) {
    // jti makes every token unique even when issued in the same second.
    const jti = randomBytes(16).toString('hex');
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { role: true },
    });
    const payload = { sub: userId, email, role: user?.role ?? 'USER', jti };
    const accessToken = await this.jwt.signAsync(payload, { expiresIn: ACCESS_TTL });
    const refreshToken = await this.jwt.signAsync(payload, {
      secret: process.env.JWT_REFRESH_SECRET,
      expiresIn: `${REFRESH_TTL_DAYS}d`,
    });
    // Store only a hash of the refresh token — a DB leak must not leak sessions.
    const tokenHash = this.hashToken(refreshToken);
    await this.prisma.refreshToken.create({
      data: {
        id: jti,
        tokenHash,
        userId,
        expiresAt: new Date(Date.now() + REFRESH_TTL_DAYS * 24 * 60 * 60 * 1000),
      },
    });
    return {
      accessToken,
      refreshToken,
      user: { id: userId, email, hasPin: hasPin ?? false, role: user?.role ?? 'USER' },
    };
  }
}
