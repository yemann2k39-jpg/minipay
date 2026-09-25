import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { ContactsService } from '../contacts/contacts.service';
import { TransfersService } from './transfers.service';
import { TransferDto } from './transfer.dto';

@Controller()
@UseGuards(JwtAuthGuard)
export class TransfersController {
  constructor(
    private transfers: TransfersService,
    private contacts: ContactsService,
  ) {}

  @Post('wallet/transfer')
  async transfer(
    @CurrentUser('userId') userId: string,
    @Body() dto: TransferDto,
  ) {
    let toUserId = dto.toUserId;
    if (!toUserId && dto.toEmail) {
      const user = await this.contacts.resolveUser(dto.toEmail);
      toUserId = user.id;
    }
    if (!toUserId) throw new BadRequestException('Recipient is required');
    return this.transfers.transfer(
      userId,
      toUserId,
      BigInt(dto.amount),
      dto.pin,
    );
  }

  @Get('notifications')
  list(@CurrentUser('userId') userId: string) {
    return this.transfers.listNotifications(userId);
  }

  @Get('notifications/unread-count')
  unread(@CurrentUser('userId') userId: string) {
    return this.transfers.unreadCount(userId);
  }

  @Post('notifications/:id/read')
  async read(@CurrentUser('userId') userId: string, @Param('id') id: string) {
    return this.transfers.markRead(userId, id);
  }

  @Post('notifications/read-all')
  async readAll(@CurrentUser('userId') userId: string) {
    return this.transfers.markAllRead(userId);
  }
}
