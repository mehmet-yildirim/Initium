# proxy.ts with CSP nonces and security headers (Next.js 16)

`proxy.ts` sits at the project root (or `src/`), exports `proxy`, and runs on Node.js. Nonces
require dynamic rendering: Next.js reads the nonce from the request's `Content-Security-Policy`
header and applies it to framework scripts automatically.

```ts
// proxy.ts
import { NextResponse, type NextRequest } from 'next/server';

const IS_DEV = process.env.NODE_ENV === 'development';

function buildCsp(nonce: string): string {
  return [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'${IS_DEV ? " 'unsafe-eval'" : ''}`,
    `style-src 'self' ${IS_DEV ? "'unsafe-inline'" : `'nonce-${nonce}'`}`,
    "img-src 'self' blob: data:",
    "font-src 'self'",
    "connect-src 'self'",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    'upgrade-insecure-requests',
  ].join('; ');
}

export function proxy(request: NextRequest) {
  const nonce = Buffer.from(crypto.randomUUID()).toString('base64');
  const csp = buildCsp(nonce);

  const requestHeaders = new Headers(request.headers);
  requestHeaders.set('x-nonce', nonce);
  requestHeaders.set('Content-Security-Policy', csp);

  const response = NextResponse.next({ request: { headers: requestHeaders } });
  response.headers.set('Content-Security-Policy', csp);
  response.headers.set('X-Content-Type-Options', 'nosniff');
  response.headers.set('Referrer-Policy', 'strict-origin-when-cross-origin');
  response.headers.set('Strict-Transport-Security', 'max-age=63072000; includeSubDomains; preload');
  return response;
}

export const config = {
  matcher: [
    {
      source: '/((?!api|_next/static|_next/image|favicon.ico).*)',
      missing: [
        { type: 'header', key: 'next-router-prefetch' },
        { type: 'header', key: 'purpose', value: 'prefetch' },
      ],
    },
  ],
};
```

- `'unsafe-eval'` is only needed in development (React debugging); never ship it.
- Add third-party origins explicitly (`connect-src`, `img-src`, `script-src`) — no wildcards.
- Read the nonce in a Server Component with `(await headers()).get('x-nonce')` and pass it to
  `<Script nonce={nonce}>` for third-party scripts.
- Pages using nonces must render dynamically (`await connection()` from `next/server` if nothing
  else makes them dynamic). For static pages, use the experimental SRI mode
  (`experimental.sri.algorithm`) with a hash-based CSP in `headers()` instead.
- Start with `Content-Security-Policy-Report-Only` plus a `report-to` endpoint in staging, then
  enforce.

## What not to do in proxy

- No database or remote session lookups — verify a signed cookie at most, and re-check the session
  in the data-access layer.
- No authorization decisions that are not repeated in Server Actions/Route Handlers: Server
  Functions are POSTs to the page route, so a matcher change silently removes coverage.
