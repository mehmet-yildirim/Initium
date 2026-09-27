# TypeScript / Node.js security examples

Assumes Node.js 24 LTS, TypeScript 5.x, Zod 4, `jose` for JWT. Language rules: `lang-typescript`;
service structure: `be-node`.

## Injection

```typescript
// BAD — SQL built from input
await db.query(`SELECT * FROM users WHERE email = '${email}'`);
// GOOD — placeholders
await db.query('SELECT * FROM users WHERE email = $1', [email]);

// BAD — shell interpolation
exec(`git clone ${repoUrl}`);
// GOOD — argument array, no shell; validate repoUrl against an allowlist first
import { execFile } from 'node:child_process';
execFile('git', ['clone', '--', repoUrl]);
```

## Prototype pollution

A `JSON.parse(JSON.stringify(x))` round-trip does **not** help: `JSON.parse('{"__proto__":{...}}')`
creates an own `__proto__` key, and `Object.assign` / naive deep-merge then writes to the prototype.

```typescript
import { z } from 'zod';

// GOOD — strict schema: unknown keys (including __proto__, constructor) are rejected
const ProfileUpdate = z.strictObject({
  displayName: z.string().min(1).max(100),
  locale: z.string().max(10),
});

export function applyProfileUpdate(profile: Profile, body: unknown): Profile {
  const update = ProfileUpdate.parse(body);
  return { ...profile, ...update };
}

// GOOD — dictionaries keyed by user input have no prototype (or use Map)
const countsByTag: Record<string, number> = Object.create(null);
```

- Never deep-merge untrusted objects with a generic merge helper; merge only schema-validated data.
- Check membership with `Object.hasOwn(obj, key)`, not `key in obj`.
- Consider `node --disable-proto=delete` for services that never use `__proto__`.

## XSS

```typescript
// BAD
element.innerHTML = userInput;
// GOOD
element.textContent = userInput;

// React: only render HTML you sanitized server- or client-side
import DOMPurify from 'dompurify';
<div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(renderedMarkdown) }} />;
```

- Ship a strict CSP (`script-src 'self'` plus nonces or hashes; no `unsafe-inline`), and Trusted
  Types where supported.

## Tokens, JWT, constant-time compare

```typescript
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { jwtVerify } from 'jose';

export const newSessionToken = (): string => randomBytes(32).toString('base64url');

// timingSafeEqual throws on length mismatch; hashing both sides gives equal lengths
export function constantTimeEquals(a: string, b: string): boolean {
  const digestA = createHash('sha256').update(a).digest();
  const digestB = createHash('sha256').update(b).digest();
  return timingSafeEqual(digestA, digestB);
}

// Never decode a JWT without verifying; pin algorithms, issuer and audience
export async function verifyAccessToken(token: string, key: Uint8Array, config: JwtConfig) {
  const { payload } = await jwtVerify(token, key, {
    algorithms: ['HS256'],
    issuer: config.issuer,
    audience: config.audience,
  });
  return payload;
}
```

## Path traversal

```typescript
import { readFile } from 'node:fs/promises';
import path from 'node:path';

const UPLOAD_DIR = path.resolve('uploads');

export async function readUpload(fileName: string): Promise<Buffer> {
  const target = path.resolve(UPLOAD_DIR, fileName);
  if (!target.startsWith(UPLOAD_DIR + path.sep)) {
    throw new PathTraversalError(fileName);
  }
  return readFile(target);
}
```

- If the directory can contain symlinks, compare `fs.realpath(target)` against the root instead.
- Prefer server-generated IDs as storage keys over user-supplied names.

## SSRF (A01)

```typescript
import { lookup } from 'node:dns/promises';
import { BlockList } from 'node:net';

const ALLOWED_HOSTS = new Set(['api.partner.example']);

const BLOCKED = new BlockList();
for (const [net, prefix] of [
  ['0.0.0.0', 8], ['10.0.0.0', 8], ['100.64.0.0', 10], ['127.0.0.0', 8],
  ['169.254.0.0', 16], ['172.16.0.0', 12], ['192.168.0.0', 16],
] as const) BLOCKED.addSubnet(net, prefix, 'ipv4');
for (const [net, prefix] of [
  ['::1', 128], ['fc00::', 7], ['fe80::', 10], ['::ffff:0:0', 96],
] as const) BLOCKED.addSubnet(net, prefix, 'ipv6');

export async function fetchPartnerResource(rawUrl: string, signal: AbortSignal): Promise<Response> {
  const url = new URL(rawUrl);
  if (url.protocol !== 'https:' || !ALLOWED_HOSTS.has(url.hostname)) {
    throw new SsrfBlockedError(url.hostname);
  }
  const addresses = await lookup(url.hostname, { all: true });
  const isBlocked = addresses.some(({ address, family }) =>
    BLOCKED.check(address, family === 6 ? 'ipv6' : 'ipv4'),
  );
  if (isBlocked) throw new SsrfBlockedError(url.hostname);
  return fetch(url, { redirect: 'error', signal });
}
```

- The host allowlist is the primary control; the IP check is defence in depth. DNS can change
  between check and connect, so route such traffic through an egress proxy for high-risk features.

## Exceptional conditions (A10)

```typescript
// Fail closed: an unavailable policy engine means "deny", never "allow"
export async function canReadDocument(actorId: string, documentId: string): Promise<boolean> {
  try {
    return await policy.isAllowed({ actorId, action: 'document:read', resource: documentId });
  } catch (error) {
    logger.error({ err: error, actorId, documentId }, 'policy check failed; denying access');
    return false;
  }
}

// Edge mapping: typed errors to RFC 9457 problem details; unknown errors to a generic 500
export function toProblem(error: unknown, instance: string): ProblemDetails {
  if (error instanceof AccessDeniedError) {
    return { type: 'https://errors.example.com/forbidden', title: 'Forbidden', status: 403, instance };
  }
  logger.error({ err: error, instance }, 'unhandled error');
  return { type: 'about:blank', title: 'Internal Server Error', status: 500, instance };
}
```

## Tooling

- `npm audit --audit-level=high` (or `pnpm audit`) in CI; `npm ci` in builds; lockfile committed.
- Keep install-script protections on (npm `ignore-scripts`, pnpm's default build-script
  blocking); allow scripts per package with a documented reason — see `security-supply-chain`.
- `eslint-plugin-security` plus Semgrep `p/typescript` and `p/react` rulesets.
