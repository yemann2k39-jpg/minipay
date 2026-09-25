import {
  BadRequestException,
  Controller,
  Post,
  RawBodyRequest,
  Req,
  Logger,
} from '@nestjs/common';
import type { Request } from 'express';
import type Stripe from 'stripe';
import { InjectStripeClient } from '../stripe/stripe.decorator';
import { WalletService } from '../wallet/wallet.service';

@Controller('payments')
export class PaymentsController {
  private readonly logger = new Logger(PaymentsController.name);

  constructor(
    @InjectStripeClient() private stripe: Stripe,
    private wallet: WalletService,
  ) {}

  /**
   * Stripe webhook — the single source of truth for deposit completion.
   * Signature-verified against STRIPE_WEBHOOK_SECRET (from `stripe listen`).
   */
  @Post('webhook')
  async webhook(@Req() req: RawBodyRequest<Request> | any) {
    const secret = process.env.STRIPE_WEBHOOK_SECRET;
    const signature = req.headers['stripe-signature'];
    if (!secret || !signature) {
      throw new BadRequestException('Missing webhook secret or signature');
    }

    let event: Stripe.Event;
    try {
      event = this.stripe.webhooks.constructEvent(
        req.rawBody!,
        signature,
        secret,
      );
    } catch (err) {
      this.logger.warn(`Webhook signature verification failed: ${err}`);
      throw new BadRequestException('Invalid webhook signature');
    }

    switch (event.type) {
      case 'payment_intent.succeeded': {
        const pi = event.data.object as Stripe.PaymentIntent;
        try {
          const res = await this.wallet.completeDeposit(pi.id);
          this.logger.log(
            `payment_intent.succeeded ${pi.id}: ${JSON.stringify(res)}`,
          );
        } catch (err) {
          // Ledger rejections (e.g. account frozen) must not 4xx Stripe:
          // we log and ack so Stripe doesn't retry a permanent failure.
          this.logger.error(
            `Could not complete deposit ${pi.id}: ${err}`,
          );
        }
        break;
      }
      case 'payment_intent.payment_failed': {
        const pi = event.data.object as Stripe.PaymentIntent;
        await this.wallet.failDeposit(
          pi.id,
          pi.last_payment_error?.message ?? 'unknown',
        );
        break;
      }
      default:
        this.logger.debug(`Unhandled webhook event: ${event.type}`);
    }
    return { received: true };
  }
}
