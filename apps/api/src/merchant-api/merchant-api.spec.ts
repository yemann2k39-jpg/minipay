import { createHmac } from 'crypto';
import {
  CheckoutInput,
  computeCallbackSignature,
  generateApiKey,
  hashApiKey,
  isSessionExpired,
  validateCheckoutInput,
} from './merchant-api.service';
import { escapeHtml, formatSgd } from '../checkout/checkout-format';

describe('merchant API keys', () => {
  it('generates keys in mp_<32 hex> format', () => {
    const key = generateApiKey();
    expect(key).toMatch(/^mp_[0-9a-f]{32}$/);
    // Randomness sanity: two keys differ.
    expect(generateApiKey()).not.toBe(key);
  });

  it('hashes keys with SHA-256 (lookup key)', () => {
    const key = 'mp_0123456789abcdef0123456789abcdef';
    const hash = hashApiKey(key);
    expect(hash).toHaveLength(64);
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
    expect(hashApiKey(key)).toBe(hashApiKey(key));
    expect(hashApiKey('mp_other')).not.toBe(hash);
  });
});

describe('computeCallbackSignature (HMAC-SHA256 known answers)', () => {
  it('matches a manually computed HMAC', () => {
    const apiKey = 'mp_0123456789abcdef0123456789abcdef';
    const body = JSON.stringify({
      event: 'checkout.paid',
      checkoutId: '7c9e6679-7425-40de-944b-e07fc1f90ae7',
      orderRef: 'ORDER-1024',
      amountMinor: '15900',
      currency: 'SGD',
      paidAt: '2026-10-23T10:05:31.000Z',
    });
    const expected = createHmac('sha256', apiKey).update(body).digest('hex');
    expect(computeCallbackSignature(body, apiKey)).toBe(expected);
    expect(expected).toMatch(/^[0-9a-f]{64}$/);
  });

  it('matches the RFC 4231 test vector (key="key", data="The quick brown fox jumps over the lazy dog")', () => {
    // Known answer: HMAC-SHA256("key", "The quick brown fox jumps over the lazy dog")
    expect(computeCallbackSignature('The quick brown fox jumps over the lazy dog', 'key')).toBe(
      'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8',
    );
  });

  it('changes when the raw body differs (merchant must sign raw body)', () => {
    const apiKey = 'mp_k';
    expect(computeCallbackSignature('{"a":1}', apiKey)).not.toBe(
      computeCallbackSignature('{"a": 1}', apiKey),
    );
  });
});

describe('validateCheckoutInput', () => {
  const valid: CheckoutInput = {
    orderRef: 'ORDER-1024',
    amountMinor: 15900,
    description: '2x GPU cable',
    callbackUrl: 'https://shop.example.com/minipay/callback',
  };

  it('accepts a valid payload', () => {
    expect(validateCheckoutInput(valid)).toEqual([]);
  });

  it('accepts missing optional description when merchant default callback exists', () => {
    expect(
      validateCheckoutInput(
        { orderRef: 'R1', amountMinor: 100 },
        'https://default.example.com/cb',
      ),
    ).toEqual([]);
  });

  it('requires a callbackUrl when the merchant has no default', () => {
    const problems = validateCheckoutInput({ orderRef: 'R1', amountMinor: 100 });
    expect(problems.join(' ')).toMatch(/callbackUrl/i);
  });

  it('rejects empty / over-long orderRef', () => {
    expect(validateCheckoutInput({ ...valid, orderRef: '' }).join(' ')).toMatch(/orderRef/i);
    expect(
      validateCheckoutInput({ ...valid, orderRef: 'x'.repeat(141) }).join(' '),
    ).toMatch(/orderRef/i);
  });

  it('rejects non-integer and out-of-range amounts', () => {
    expect(
      validateCheckoutInput({ ...valid, amountMinor: 10.5 }).join(' '),
    ).toMatch(/amountMinor/i);
    expect(validateCheckoutInput({ ...valid, amountMinor: 0 }).join(' ')).toMatch(/amountMinor/i);
    expect(
      validateCheckoutInput({ ...valid, amountMinor: 5_000_001 }).join(' '),
    ).toMatch(/amountMinor/i);
    // Boundary values are fine.
    expect(validateCheckoutInput({ ...valid, amountMinor: 1 })).toEqual([]);
    expect(validateCheckoutInput({ ...valid, amountMinor: 5_000_000 })).toEqual([]);
  });

  it('rejects descriptions over 280 chars', () => {
    expect(
      validateCheckoutInput({ ...valid, description: 'd'.repeat(281) }).join(' '),
    ).toMatch(/description/i);
  });

  it('rejects non-https callback URLs', () => {
    expect(
      validateCheckoutInput({ ...valid, callbackUrl: 'http://shop.example.com/cb' }).join(' '),
    ).toMatch(/callbackUrl/i);
  });
});

describe('isSessionExpired (lazy expiry)', () => {
  const now = new Date('2026-10-23T10:00:00.000Z');

  it('is true only for PENDING sessions past expiry', () => {
    expect(
      isSessionExpired(
        { status: 'PENDING', expiresAt: new Date('2026-10-23T09:59:59.999Z') },
        now,
      ),
    ).toBe(true);
  });

  it('is false for PENDING sessions not yet expired', () => {
    expect(
      isSessionExpired(
        { status: 'PENDING', expiresAt: new Date('2026-10-23T10:00:00.000Z') },
        now,
      ),
    ).toBe(false);
  });

  it('is false for PAID / EXPIRED sessions regardless of expiry time', () => {
    expect(
      isSessionExpired(
        { status: 'PAID', expiresAt: new Date('2020-01-01T00:00:00.000Z') },
        now,
      ),
    ).toBe(false);
    expect(
      isSessionExpired(
        { status: 'EXPIRED', expiresAt: new Date('2020-01-01T00:00:00.000Z') },
        now,
      ),
    ).toBe(false);
  });
});

describe('hosted page helpers', () => {
  it('escapeHtml neutralizes HTML-special characters', () => {
    expect(escapeHtml(`<img src=x onerror="alert('x')">&`)).toBe(
      '&lt;img src=x onerror=&quot;alert(&#39;x&#39;)&quot;&gt;&amp;',
    );
  });

  it('formatSgd renders minor units as SGD', () => {
    expect(formatSgd(15900n)).toBe('S$159.00');
    expect(formatSgd(5n)).toBe('S$0.05');
    expect(formatSgd(100n)).toBe('S$1.00');
  });
});
