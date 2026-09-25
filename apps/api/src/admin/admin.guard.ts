import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
} from '@nestjs/common';

/** Allows only users whose JWT carries role ADMIN. */
@Injectable()
export class AdminGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest();
    if (request.user?.role !== 'ADMIN') {
      throw new ForbiddenException('Admin access only');
    }
    return true;
  }
}
