# SSRF guard for user-influenced outbound URLs (Node 24)

Read before writing a webhook sender, URL preview/fetcher, image proxy, or any adapter whose
target URL comes from a user, tenant configuration, or third-party payload (OWASP API7:2023).

## Rules

- Allowlist first: scheme `https:` only, no credentials in the URL, host in a configured set.
  Webhook-style features that must reach arbitrary hosts skip the host allowlist but keep every
  other check and send traffic through a dedicated egress proxy.
- Resolve the hostname and reject if any resolved address is private, loopback, link-local
  (includes cloud metadata `169.254.169.254`), CGNAT, multicast, or reserved.
- Disable automatic redirects (`redirect: 'manual'`); validate each `Location` with the same guard
  or treat 3xx as failure.
- Always set a timeout and a response size cap; never return raw upstream bodies or errors to
  the caller.
- DNS can change between the check and the connection (rebinding). The in-process check is a
  first line; enforce the same ranges in an egress network policy or proxy.

## Guard

```ts
// src/outbound/safe-url.ts
import { lookup } from 'node:dns/promises';
import { BlockList } from 'node:net';
import { err, ok, type Result } from '../shared/result.js';

export type UrlRejection = 'INVALID_URL' | 'SCHEME_NOT_ALLOWED' | 'HOST_NOT_ALLOWED' | 'PRIVATE_ADDRESS';

const BLOCKED_IPV4: ReadonlyArray<readonly [string, number]> = [
  ['0.0.0.0', 8], ['10.0.0.0', 8], ['100.64.0.0', 10], ['127.0.0.0', 8],
  ['169.254.0.0', 16], ['172.16.0.0', 12], ['192.0.0.0', 24], ['192.168.0.0', 16],
  ['198.18.0.0', 15], ['224.0.0.0', 4], ['240.0.0.0', 4],
];

const BLOCKED_IPV6: ReadonlyArray<readonly [string, number]> = [
  ['::', 128], ['::1', 128], ['::ffff:0:0', 96], ['64:ff9b::', 96],
  ['fc00::', 7], ['fe80::', 10], ['ff00::', 8],
];

const blockList = new BlockList();
for (const [network, prefix] of BLOCKED_IPV4) blockList.addSubnet(network, prefix, 'ipv4');
for (const [network, prefix] of BLOCKED_IPV6) blockList.addSubnet(network, prefix, 'ipv6');

/** Returns the parsed URL only if it is safe to request from this service. */
export async function checkOutboundUrl(
  raw: string,
  allowedHosts: ReadonlySet<string> | 'any-public-host',
): Promise<Result<URL, UrlRejection>> {
  if (!URL.canParse(raw)) return err('INVALID_URL');
  const url = new URL(raw);

  if (url.protocol !== 'https:') return err('SCHEME_NOT_ALLOWED');
  if (url.username !== '' || url.password !== '') return err('INVALID_URL');
  if (allowedHosts !== 'any-public-host' && !allowedHosts.has(url.hostname)) return err('HOST_NOT_ALLOWED');

  const addresses = await lookup(url.hostname, { all: true, verbatim: true });
  const hasBlockedAddress = addresses.some(({ address, family }) =>
    blockList.check(address, family === 6 ? 'ipv6' : 'ipv4'),
  );
  if (hasBlockedAddress) return err('PRIVATE_ADDRESS');

  return ok(url);
}
```

## Adapter usage

```ts
// src/webhooks/adapters/http-webhook-sender.ts
import type { Logger } from 'pino';
import { checkOutboundUrl } from '../../outbound/safe-url.js';
import { err, ok, type Result } from '../../shared/result.js';
import type { WebhookSender } from '../ports/webhook-sender.js';

const WEBHOOK_TIMEOUT_MS = 5_000;

export function createHttpWebhookSender(logger: Logger): WebhookSender {
  return {
    async send(targetUrl: string, body: string): Promise<Result<void, 'TARGET_REJECTED' | 'DELIVERY_FAILED'>> {
      const checked = await checkOutboundUrl(targetUrl, 'any-public-host');
      if (!checked.ok) {
        logger.warn({ reason: checked.error }, 'webhook target rejected');
        return err('TARGET_REJECTED');
      }

      const response = await fetch(checked.value, {
        method: 'POST',
        body,
        headers: { 'content-type': 'application/json' },
        redirect: 'manual',
        signal: AbortSignal.timeout(WEBHOOK_TIMEOUT_MS),
      });
      await response.body?.cancel();
      if (!response.ok) {
        logger.warn({ status: response.status }, 'webhook delivery failed');
        return err('DELIVERY_FAILED');
      }
      return ok(undefined);
    },
  };
}
```

Log the rejection reason and host, never the full URL if it can carry tokens in the query string.
Network errors and timeouts from `fetch` propagate to the caller's retry policy.
