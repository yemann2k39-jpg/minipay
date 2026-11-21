import {
  Body,
  Controller,
  Get,
  Patch,
  Post,
  Put,
  Req,
  UseGuards,
} from '@nestjs/common';
import type { Request } from 'express';
import { AuthService, SessionMeta } from './auth.service';
import { RegisterDto } from './dto/register.dto';
import { RegisterBusinessDto } from './dto/register-business.dto';
import { LoginDto } from './dto/login.dto';
import { RefreshDto } from './dto/refresh.dto';
import { SetupPinDto } from './dto/setup-pin.dto';
import { JwtAuthGuard } from './jwt-auth.guard';
import { CurrentUser } from './current-user.decorator';

@Controller('auth')
export class AuthController {
  constructor(private auth: AuthService) {}

  @Post('register')
  register(@Body() dto: RegisterDto) {
    return this.auth.register(dto);
  }

  /** Register a business account (merchant user + shop + ledger, one call). */
  @Post('register-business')
  registerBusiness(@Body() dto: RegisterBusinessDto) {
    return this.auth.registerBusiness(dto);
  }

  @Post('login')
  login(@Body() dto: LoginDto, @Req() req: Request) {
    return this.auth.login(dto, this.sessionMeta(req));
  }

  @Post('refresh')
  refresh(@Body() dto: RefreshDto, @Req() req: Request) {
    return this.auth.refresh(dto.refreshToken, this.sessionMeta(req));
  }

  @Post('logout')
  logout(@Body() dto: RefreshDto) {
    return this.auth.logout(dto.refreshToken);
  }

  @Get('me')
  @UseGuards(JwtAuthGuard)
  me(
    @CurrentUser('userId') userId: string,
    @CurrentUser('email') email: string,
  ) {
    return this.auth.me(userId, email);
  }

  @Post('pin')
  @UseGuards(JwtAuthGuard)
  setupPin(@CurrentUser('userId') userId: string, @Body() dto: SetupPinDto) {
    return this.auth.setupPin(userId, dto.pin);
  }

  @Get('pin/status')
  @UseGuards(JwtAuthGuard)
  pinStatus(@CurrentUser('userId') userId: string) {
    return this.auth.hasPin(userId);
  }

  /** Verify a payment PIN — used by the app-lock (biometric/PIN unlock). */
  @Post('pin/verify')
  @UseGuards(JwtAuthGuard)
  verifyPin(@CurrentUser('userId') userId: string, @Body() dto: SetupPinDto) {
    return this.auth.verifyPin(userId, dto.pin);
  }

  // -- Profile & security management (PGW-29/30/31) ------------------------

  /** Update profile (display name). */
  @Patch('me')
  @UseGuards(JwtAuthGuard)
  updateProfile(
    @CurrentUser('userId') userId: string,
    @Body() body: { displayName?: string },
  ) {
    return this.auth.updateProfile(userId, body ?? {});
  }

  /** Wallet preferences (daily spend limit). */
  @Put('preferences')
  @UseGuards(JwtAuthGuard)
  setPreferences(
    @CurrentUser('userId') userId: string,
    @Body() body: { dailySpendLimitMinor?: number | null },
  ) {
    return this.auth.setPreferences(userId, body ?? {});
  }

  @Get('preferences')
  @UseGuards(JwtAuthGuard)
  getPreferences(@CurrentUser('userId') userId: string) {
    return this.auth.getPreferences(userId);
  }

  /** Change password; revokes all other sessions. */
  @Post('change-password')
  @UseGuards(JwtAuthGuard)
  changePassword(
    @CurrentUser('userId') userId: string,
    @CurrentUser('jti') jti: string,
    @Body() body: { currentPassword?: string; newPassword?: string },
  ) {
    return this.auth.changePassword(
      userId,
      body?.currentPassword ?? '',
      body?.newPassword ?? '',
      jti,
    );
  }

  /** Change payment PIN (requires current PIN). */
  @Post('pin/change')
  @UseGuards(JwtAuthGuard)
  changePin(
    @CurrentUser('userId') userId: string,
    @Body() body: { currentPin?: string; newPin?: string },
  ) {
    return this.auth.changePin(userId, body?.currentPin ?? '', body?.newPin ?? '');
  }

  /** Forgot-PIN path: prove identity with account password. */
  @Post('pin/reset')
  @UseGuards(JwtAuthGuard)
  resetPin(
    @CurrentUser('userId') userId: string,
    @Body() body: { password?: string; newPin?: string },
  ) {
    return this.auth.resetPin(userId, body?.password ?? '', body?.newPin ?? '');
  }

  /** Active sessions for the account (PGW-31). */
  @Get('sessions')
  @UseGuards(JwtAuthGuard)
  sessions(@CurrentUser('userId') userId: string, @CurrentUser('jti') jti: string) {
    return this.auth.listSessions(userId, jti);
  }

  /** Revoke all sessions except the current one (PGW-31). */
  @Post('logout-others')
  @UseGuards(JwtAuthGuard)
  logoutOthers(@CurrentUser('userId') userId: string, @CurrentUser('jti') jti: string) {
    return this.auth.logoutOthers(userId, jti);
  }

  private sessionMeta(req: Request): SessionMeta {
    return {
      userAgent: typeof req.headers['user-agent'] === 'string' ? req.headers['user-agent'] : undefined,
      ip: req.ip,
    };
  }
}
