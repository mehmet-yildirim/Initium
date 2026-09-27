# Node.js Dockerfile (Node 24, distroless runtime)

Three stages: production dependencies, build, and a distroless runtime that receives only
`dist/` and production `node_modules`. Pin every `FROM` by digest in real projects
(`node:24-slim@sha256:...`); digests are omitted here because they change weekly.

```dockerfile
# syntax=docker/dockerfile:1

# ---- Production dependencies only ----
FROM node:24-slim AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --omit=dev

# ---- Build (all dependencies) ----
FROM node:24-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci
COPY . .
RUN npm run build

# ---- Runtime ----
FROM gcr.io/distroless/nodejs24-debian13:nonroot AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY --from=deps  --chown=nonroot:nonroot /app/node_modules ./node_modules
COPY --from=build --chown=nonroot:nonroot /app/dist ./dist
USER nonroot
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["/nodejs/bin/node", "dist/healthcheck.js"]
# distroless nodejs sets ENTRYPOINT ["/nodejs/bin/node"]; CMD is the script.
CMD ["dist/server.js"]
```

Notes:

- `HEALTHCHECK` is honoured by Docker and Compose only. Kubernetes ignores it — define
  `startupProbe`/`readinessProbe`/`livenessProbe` instead (see `devops-kubernetes`). Drop the
  `HEALTHCHECK` line if the image only ever runs on Kubernetes.
- Private registry: add a secret mount to both `npm ci` steps and reference the token from
  `.npmrc` as `//registry.npmjs.org/:_authToken=${NPM_TOKEN}`:

  ```dockerfile
  RUN --mount=type=cache,target=/root/.npm \
      --mount=type=secret,id=npm_token,env=NPM_TOKEN,required=true \
      npm ci --omit=dev
  ```

  Build with `docker buildx build --secret id=npm_token,env=NPM_TOKEN .`
- Native modules compiled in `deps` must match the runtime's libc: `node:24-slim` and
  `distroless/*-debian13` are both glibc-based. Do not mix Alpine (musl) build stages with a
  Debian runtime.

## Health check script

Compiled from `src/healthcheck.ts` into `dist/healthcheck.js` (ESM). It uses the built-in
`fetch`, so no `wget`/`curl` is needed in the image.

```typescript
const HEALTH_URL = 'http://127.0.0.1:3000/health/live';
const TIMEOUT_MS = 2_000;

try {
  const response = await fetch(HEALTH_URL, { signal: AbortSignal.timeout(TIMEOUT_MS) });
  process.exitCode = response.ok ? 0 : 1;
} catch {
  // Unreachable or timed out: report unhealthy; the container runtime records the exit code.
  process.exitCode = 1;
}
```

## .dockerignore

```
.git
.github
node_modules
dist
coverage
.env
.env.*
*.log
**/*.test.*
**/*.spec.*
Dockerfile*
compose*.y*ml
docker-compose*.y*ml
```

Keep documentation out only if the build does not need it; never exclude files that `npm run
build` reads (for example `tsconfig*.json`).
