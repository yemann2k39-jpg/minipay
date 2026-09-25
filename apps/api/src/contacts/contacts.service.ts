import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class ContactsService {
  constructor(private prisma: PrismaService) {}

  /** Find a user by email or phone (for adding a contact). */
  async resolveUser(query: string) {
    const q = query.trim().toLowerCase();
    if (!q) throw new BadRequestException('Enter an email or phone number');
    const user = await this.prisma.user.findFirst({
      where: { OR: [{ email: q }, { phone: query.trim() }] },
      select: { id: true, displayName: true, email: true, phone: true, status: true },
    });
    if (!user || user.status !== 'ACTIVE') {
      throw new NotFoundException('No MiniPay user found with that email or phone');
    }
    return user;
  }

  /** Public-ish lookup for the Transfer screen: verify recipient exists. */
  async lookup(query: string) {
    const user = await this.resolveUser(query);
    return { userId: user.id, displayName: user.displayName, email: user.email };
  }

  async list(userId: string) {
    const contacts = await this.prisma.contact.findMany({
      where: { ownerId: userId },
      orderBy: { createdAt: 'desc' },
      include: {
        contact: { select: { id: true, displayName: true, email: true, phone: true } },
      },
    });
    return contacts.map((c) => ({
      id: c.id,
      userId: c.contact.id,
      displayName: c.alias ?? c.contact.displayName,
      email: c.contact.email,
      phone: c.contact.phone,
    }));
  }

  async add(userId: string, query: string, alias?: string) {
    const target = await this.resolveUser(query);
    if (target.id === userId) {
      throw new BadRequestException('You cannot add yourself as a contact');
    }
    const dup = await this.prisma.contact.findUnique({
      where: { ownerId_contactId: { ownerId: userId, contactId: target.id } },
    });
    if (dup) throw new BadRequestException('Already in your contacts');
    const contact = await this.prisma.contact.create({
      data: { ownerId: userId, contactId: target.id, alias },
    });
    return {
      id: contact.id,
      userId: target.id,
      displayName: alias ?? target.displayName,
      email: target.email,
      phone: target.phone,
    };
  }

  async remove(userId: string, contactId: string) {
    const c = await this.prisma.contact.findUnique({ where: { id: contactId } });
    if (!c || c.ownerId !== userId) throw new NotFoundException('Contact not found');
    await this.prisma.contact.delete({ where: { id: contactId } });
    return { success: true };
  }

  async search(userId: string, q: string) {
    const query = q.trim();
    if (query.length < 3) {
      throw new BadRequestException('Search needs at least 3 characters');
    }
    const users = await this.prisma.user.findMany({
      where: {
        id: { not: userId },
        status: 'ACTIVE',
        OR: [
          { email: { contains: query, mode: 'insensitive' } },
          { displayName: { contains: query, mode: 'insensitive' } },
          { phone: { contains: query } },
        ],
      },
      select: { id: true, displayName: true, email: true, phone: true },
      take: 10,
    });
    const mine = await this.prisma.contact.findMany({
      where: { ownerId: userId },
      select: { contactId: true },
    });
    const mineSet = new Set(mine.map((m) => m.contactId));
    return users.map((u) => ({
      userId: u.id,
      displayName: u.displayName,
      email: u.email,
      phone: u.phone,
      alreadyAdded: mineSet.has(u.id),
    }));
  }
}
