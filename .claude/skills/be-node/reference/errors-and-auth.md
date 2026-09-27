# Typed errors, RFC 9457 mapping, and JWT verification (Fastify 5, Zod 4, jose 6)

Read when implementing a service's error handler, a domain error type, or the bearer-token
adapter. The problem+json contract itself is defined in `api-rest-openapi`.

## Result type and domain errors

```ts
// src/shared/result.ts
export type Result<T, E> = { ok: true; value: T } | { ok: false; error: E };

export const ok = <T>(value: T): Result<T, never> => ({ ok: true, value });
export const err = <E>(error: E): Result<never, E> => ({ ok: false, error });
```

```ts
// src/orders/domain/order-errors.ts
export type OrderError =
  | { code: 'ORDER_NOT_FOUND'; orderId: string }
  | { code: 'ORDER_ALREADY_PAID'; orderId: string };
```

Use cases return `Result<Order, OrderError>`; they never import Fastify or build HTTP responses.

## Mapping to problem+json at the edge

```ts
// src/http/problem.ts
import type { FastifyReply } from 'fastify';
import type { ZodError } from 'zod';
import type { OrderError } from '../orders/domain/order-errors.js';

const PROBLEM_TYPE_BASE = 'https://errors.example.com/';

export interface ProblemDetails {
  type: string;
  title: string;
  status: number;
  code: string;
  detail?: string;
  instance?: string;
  errors?: ReadonlyArray<{ pointer: string; detail: string }>;
}

const ORDER_ERROR_HTTP: Record<OrderError['code'], { status: number; title: string }> = {
  ORDER_NOT_FOUND: { status: 404, title: 'Order not found' },
  ORDER_ALREADY_PAID: { status: 409, title: 'Order already paid' },
};

export function orderProblem(error: OrderError): ProblemDetails {
  const { status, title } = ORDER_ERROR_HTTP[error.code];
  return { type: `${PROBLEM_TYPE_BASE}${error.code.toLowerCase()}`, title, status, code: error.code };
}

export const UNAUTHORIZED: ProblemDetails = {
  type: 'about:blank',
  title: 'Unauthorized',
  status: 401,
  code: 'UNAUTHENTICATED',
};

export function validationProblem(error: ZodError): ProblemDetails {
  return {
    type: `${PROBLEM_TYPE_BASE}validation-failed`,
    title: 'Request validation failed',
    status: 422,
    code: 'VALIDATION_FAILED',
    errors: error.issues.map((issue) => ({
      pointer: `/${issue.path.map(String).join('/')}`,
      detail: issue.message,
    })),
  };
}

export function sendProblem(reply: FastifyReply, problem: ProblemDetails): FastifyReply {
  return reply
    .status(problem.status)
    .type('application/problem+json')
    .send({ ...problem, instance: `urn:uuid:${reply.request.id}` });
}
```

```ts
// src/orders/http/order.routes.ts
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { orderProblem, sendProblem, UNAUTHORIZED, validationProblem } from '../../http/problem.js';
import type { GetOrder } from '../application/get-order.js';

const OrderParams = z.strictObject({ orderId: z.uuid() });

export function registerOrderRoutes(app: FastifyInstance, getOrder: GetOrder): void {
  app.get('/orders/:orderId', async (request, reply) => {
    const params = OrderParams.safeParse(request.params);
    if (!params.success) return sendProblem(reply, validationProblem(params.error));
    if (!request.principal) return sendProblem(reply, UNAUTHORIZED);

    const result = await getOrder.execute({
      callerId: request.principal.subject,
      orderId: params.data.orderId,
    });
    if (!result.ok) return sendProblem(reply, orderProblem(result.error));
    return reply.send(result.value);
  });
}
```

`getOrder.execute` enforces ownership and returns `ORDER_NOT_FOUND` for other users' orders, so
the response does not reveal whether the id exists.

## Global handler for everything unexpected

```ts
// src/http/app.ts
import { randomUUID } from 'node:crypto';
import Fastify from 'fastify';
import { sendProblem } from './problem.js';

export const app = Fastify({
  genReqId: () => randomUUID(),
  bodyLimit: 1_048_576,
  logger: { redact: ['req.headers.authorization', 'req.headers.cookie'] },
});

app.setErrorHandler((error: unknown, request, reply) => {
  const statusCode =
    typeof error === 'object' && error !== null && 'statusCode' in error && typeof error.statusCode === 'number'
      ? error.statusCode
      : 500;

  if (statusCode >= 500) {
    request.log.error({ err: error }, 'unhandled error');
    return sendProblem(reply, { type: 'about:blank', title: 'Internal Server Error', status: 500, code: 'INTERNAL' });
  }
  request.log.warn({ err: error }, 'request rejected by framework');
  return sendProblem(reply, { type: 'about:blank', title: 'Bad Request', status: statusCode, code: 'BAD_REQUEST' });
});
```

Framework errors below 500 (body too large, malformed JSON) keep their status; everything else is a
generic 500 with no internal detail.

## JWT verification adapter (jose 6)

```ts
// src/auth/jose-token-verifier.ts
import { createRemoteJWKSet, errors, jwtVerify } from 'jose';
import { err, ok, type Result } from '../shared/result.js';

export interface Principal {
  subject: string;
  scopes: readonly string[];
}

export type TokenError = 'TOKEN_EXPIRED' | 'TOKEN_INVALID';

export interface TokenVerifier {
  verify(token: string): Promise<Result<Principal, TokenError>>;
}

interface JoseVerifierOptions {
  jwksUrl: URL;
  issuer: string;
  audience: string;
  algorithms: string[];
}

export function createJoseTokenVerifier(options: JoseVerifierOptions): TokenVerifier {
  const jwks = createRemoteJWKSet(options.jwksUrl);

  return {
    async verify(token) {
      try {
        const { payload } = await jwtVerify(token, jwks, {
          issuer: options.issuer,
          audience: options.audience,
          algorithms: options.algorithms,
        });
        if (typeof payload.sub !== 'string') return err('TOKEN_INVALID');
        const scopes = typeof payload.scope === 'string' ? payload.scope.split(' ') : [];
        return ok({ subject: payload.sub, scopes });
      } catch (error) {
        if (error instanceof errors.JWTExpired) return err('TOKEN_EXPIRED');
        // JWKS endpoint unreachable is an infrastructure fault (503), not a bad token.
        if (error instanceof errors.JWKSTimeout) throw error;
        if (error instanceof errors.JOSEError) return err('TOKEN_INVALID');
        throw error;
      }
    },
  };
}
```

```ts
// src/http/auth.hook.ts
import type { FastifyInstance } from 'fastify';
import type { Principal, TokenVerifier } from '../auth/jose-token-verifier.js';
import { sendProblem, UNAUTHORIZED } from './problem.js';

declare module 'fastify' {
  interface FastifyRequest {
    principal: Principal | null;
  }
}

const BEARER_PREFIX = 'Bearer ';

export function registerAuth(app: FastifyInstance, verifier: TokenVerifier): void {
  app.decorateRequest('principal', null);

  app.addHook('onRequest', async (request, reply) => {
    const header = request.headers.authorization;
    const token = header?.startsWith(BEARER_PREFIX) ? header.slice(BEARER_PREFIX.length) : undefined;
    const result = token ? await verifier.verify(token) : undefined;

    if (!result?.ok) {
      request.log.info({ reason: result?.error ?? 'TOKEN_MISSING' }, 'authentication failed');
      reply.header('www-authenticate', 'Bearer error="invalid_token"');
      return sendProblem(reply, UNAUTHORIZED);
    }
    request.principal = result.value;
  });
}
```

Configuration (`jwksUrl`, `issuer`, `audience`, `algorithms`) comes from the validated config
object; pin `algorithms` to what the identity provider actually signs with (for example
`['RS256']` or `['ES256']`). Never log the token.
