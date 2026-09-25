import { Inject } from '@nestjs/common';
import { STRIPE_CLIENT } from './stripe.provider';

export const InjectStripeClient = () => Inject(STRIPE_CLIENT);
