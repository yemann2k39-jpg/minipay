import { HttpException, HttpStatus, Injectable } from '@nestjs/common';

/**
 * Legacy-app receipt prompt, kept in spirit: extract ONLY purchased items and
 * their prices, ignore totals/tax/tips, translate non-English item names to
 * English, and answer with a STRICT JSON array of {"name","price"} — no prose,
 * no markdown.
 */
const PROMPT = `You are a receipt item extractor. Look at this receipt image and list ONLY the purchased items with their prices.
Rules:
- Extract only purchased items and their individual prices.
- Do NOT include totals, subtotals, taxes, service charges, tips, change, or payment info.
- If an item name is not in English, translate it to English.
- Respond with a STRICT JSON array only, where every element is an object like {"name": "<item name>", "price": <number>}. Price is the item price in the receipt's currency.
- No markdown, no code fences, no explanations, no extra text.`;

/** 429/quota from Gemini — status 429 preserved so the client can back off. */
export class ApiLimitReachedException extends HttpException {
  constructor(message = 'Receipt scan limit reached. Please try again later.') {
    super({ statusCode: HttpStatus.TOO_MANY_REQUESTS, code: 'API_LIMIT_REACHED', message }, HttpStatus.TOO_MANY_REQUESTS);
  }
}

/** 503/unavailable from Gemini — status 503 preserved. */
export class ApiBusyException extends HttpException {
  constructor(message = 'Receipt scan service is busy. Please try again in a moment.') {
    super({ statusCode: HttpStatus.SERVICE_UNAVAILABLE, code: 'API_BUSY', message }, HttpStatus.SERVICE_UNAVAILABLE);
  }
}

interface GeminiPart {
  text?: string;
}

interface GeminiResponse {
  candidates?: { content?: { parts?: GeminiPart[] } }[];
  promptFeedback?: { blockReason?: string };
}

/** Strip ```json fences and parse a JSON array out of the model's reply. */
export function extractJsonArray(text: string): unknown {
  let t = text.trim();
  const fenced = t.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  if (fenced) t = fenced[1].trim();
  try {
    return JSON.parse(t);
  } catch {
    // Fallback: grab the outermost [...] block if the model added stray prose.
    const start = t.indexOf('[');
    const end = t.lastIndexOf(']');
    if (start !== -1 && end > start) {
      try {
        return JSON.parse(t.slice(start, end + 1));
      } catch {
        // fall through
      }
    }
    throw new HttpException(
      'Could not read the receipt. Please try a clearer photo.',
      HttpStatus.BAD_GATEWAY,
    );
  }
}

@Injectable()
export class GeminiService {
  /** Scan a receipt photo and return its items with prices in minor units. */
  async scanReceipt(
    imageBase64: string,
    mimeType: string,
  ): Promise<{ name: string; priceMinor: bigint }[]> {
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
      // Log the detail server-side; return a generic message to clients.
      console.error('[GeminiService] GEMINI_API_KEY is not configured');
      throw new HttpException(
        'Receipt scanning is temporarily unavailable.',
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
    if (!imageBase64) {
      throw new HttpException('Receipt image is required.', HttpStatus.BAD_REQUEST);
    }

    const model = process.env.GEMINI_MODEL ?? 'gemini-3.1-flash-lite';
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;

    let res: Response;
    try {
      res = await fetch(url, {
        method: 'POST',
        // Key in a header, never in the URL (kept out of proxy/access logs).
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey,
        },
        signal: AbortSignal.timeout(20_000),
        body: JSON.stringify({
          contents: [
            {
              parts: [
                { text: PROMPT },
                { inline_data: { mime_type: mimeType || 'image/jpeg', data: imageBase64 } },
              ],
            },
          ],
        }),
      });
    } catch (e) {
      if (e instanceof Error && e.name === 'TimeoutError') {
        throw new ApiBusyException('Receipt scan timed out. Please try again.');
      }
      throw new ApiBusyException('Could not reach the receipt scan service. Please try again.');
    }

    if (!res.ok) {
      if (res.status === 429) throw new ApiLimitReachedException();
      if (res.status === 503) throw new ApiBusyException();
      throw new HttpException(
        'Receipt scan failed. Please try again later.',
        HttpStatus.BAD_GATEWAY,
      );
    }

    let data: GeminiResponse;
    try {
      data = (await res.json()) as GeminiResponse;
    } catch {
      // Non-JSON upstream body (proxy error page etc.) → 502, not 500.
      throw new HttpException(
        'Receipt scan failed. Please try again later.',
        HttpStatus.BAD_GATEWAY,
      );
    }
    const text =
      data.candidates?.[0]?.content?.parts
        ?.map((p) => p.text ?? '')
        .join('') ?? '';
    if (!text) {
      throw new HttpException(
        'Could not read the receipt. Please try a clearer photo.',
        HttpStatus.BAD_GATEWAY,
      );
    }

    const parsed = extractJsonArray(text);
    if (!Array.isArray(parsed)) {
      throw new HttpException(
        'Could not read the receipt. Please try a clearer photo.',
        HttpStatus.BAD_GATEWAY,
      );
    }

    const items: { name: string; priceMinor: bigint }[] = [];
    for (const entry of parsed) {
      if (typeof entry !== 'object' || entry === null) continue;
      const { name, price } = entry as { name?: unknown; price?: unknown };
      if (typeof name !== 'string') continue;
      const trimmed = name.trim();
      if (!trimmed) continue;
      const priceNum = Number(price);
      if (!Number.isFinite(priceNum)) continue;
      const priceMinor = BigInt(Math.round(priceNum * 100));
      if (priceMinor <= 0n) continue; // spec: drop items with price <= 0
      items.push({ name: trimmed, priceMinor });
    }
    return items;
  }
}
