import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { AuthService } from './auth.service';
import { RegisterDto } from './dto/register.dto';
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

  @Post('login')
  login(@Body() dto: LoginDto) {
    return this.auth.login(dto);
  }

  @Post('refresh')
  refresh(@Body() dto: RefreshDto) {
    return this.auth.refresh(dto.refreshToken);
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
}
