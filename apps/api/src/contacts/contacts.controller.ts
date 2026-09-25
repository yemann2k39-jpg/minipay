import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { ContactsService } from './contacts.service';

export class AddContactDto {
  @IsString()
  query: string; // email or phone

  @IsOptional()
  @IsString()
  @MaxLength(50)
  alias?: string;
}

export class SearchDto {
  @IsString()
  @MinLength(3)
  q: string;
}

@Controller('contacts')
@UseGuards(JwtAuthGuard)
export class ContactsController {
  constructor(private contacts: ContactsService) {}

  @Get()
  list(@CurrentUser('userId') userId: string) {
    return this.contacts.list(userId);
  }

  @Get('search')
  search(@CurrentUser('userId') userId: string, @Query() dto: SearchDto) {
    return this.contacts.search(userId, dto.q);
  }

  /** Verify a recipient exists by email/phone — Transfer screen. */
  @Get('lookup')
  lookup(@Query('query') query: string) {
    return this.contacts.lookup(query ?? '');
  }

  @Post()
  @HttpCode(200)
  add(
    @CurrentUser('userId') userId: string,
    @Body() dto: AddContactDto,
  ) {
    return this.contacts.add(userId, dto.query, dto.alias);
  }

  @Delete(':id')
  remove(@CurrentUser('userId') userId: string, @Param('id') id: string) {
    return this.contacts.remove(userId, id);
  }
}
