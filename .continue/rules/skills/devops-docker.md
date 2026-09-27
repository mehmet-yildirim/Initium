---
name: devops-docker
description: Docker and container standards — Dockerfile best practices, compose, security, optimization. Use when writing Dockerfiles, compose files, or container runtime configuration.
globs:
  - "**/Dockerfile*"
  - "**/docker-compose*.yml"
  - "**/.dockerignore"
  - "**/containerfile*"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# Docker & Container Standards

## Dockerfile Best Practices

### Base Images
- Use official, minimal base images: `distroless`, `alpine`, or `slim` variants
- Pin exact image digests in production: `FROM node:22-alpine@sha256:<digest>`
- Multi-stage builds to separate build-time and runtime dependencies
- Never use `latest` tag in production Dockerfiles

### Multi-Stage Build Pattern
```dockerfile
# ---- Build Stage ----
FROM node:22-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --frozen-lockfile
COPY . .
RUN npm run build

# ---- Runtime Stage ----
FROM node:22-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app

# Create non-root user
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 appuser

# Copy only production artifacts
COPY --from=builder --chown=appuser:nodejs /app/dist ./dist
COPY --from=builder --chown=appuser:nodejs /app/node_modules ./node_modules

USER appuser
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:3000/health/live || exit 1
ENTRYPOINT ["node", "dist/server.js"]
```

### Layer Optimization
- Order layers from least to most frequently changing: base → system deps → app deps → source code
- Copy dependency manifests before source code to leverage Docker cache
- Combine `RUN` commands with `&&` to reduce layers
- Use `.dockerignore` to exclude: `node_modules`, `.git`, `*.log`, `.env`, `dist`, test files

### Security
- **Never run as root** — create and use a dedicated non-root user
- No secrets, credentials, or API keys in image layers (use runtime secrets)
- `--no-cache` for apk/apt when not needed beyond build: `RUN apk add --no-cache curl`
- Scan images with Trivy or Docker Scout in CI: fail on HIGH/CRITICAL CVEs
- Read-only filesystem where possible: `--read-only` flag + tmpfs for writable paths
- Drop all capabilities: `--cap-drop=ALL`; add only what's needed

## Docker Compose (Development)
```yaml
services:
  app:
    build:
      context: .
      target: runtime          # Use specific build stage
    environment:
      - NODE_ENV=development
    env_file: .env
    ports:
      - "3000:3000"
    volumes:
      - .:/app                 # Source mount for hot reload
      - /app/node_modules      # Anonymous volume to preserve container's node_modules
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - app-net

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: ${DB_NAME}
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - app-net

volumes:
  postgres_data:

networks:
  app-net:
    driver: bridge
```

### Compose Rules
- `depends_on` with `condition: service_healthy` — not just `depends_on: [service]`
- Healthchecks on all stateful services (DB, cache, queue)
- Named volumes for persistent data — not bind mounts
- Named networks — avoid default network for isolation
- `env_file: .env` instead of hardcoded environment values

## Image Tagging Strategy
- Development: `app:dev`, `app:branch-name`
- CI builds: `app:<git-sha>` (immutable, traceable)
- Production releases: `app:v1.2.3` (semantic version) + `app:latest`
- Never overwrite an existing immutable tag (SHA-based)

## Container Runtime Standards
- Set resource limits: `--memory`, `--cpus` (Kubernetes: `resources.requests` + `resources.limits`)
- Liveness and readiness probes in orchestrated environments
- Graceful shutdown: handle `SIGTERM`; drain connections before exit (30s timeout)
- Log to stdout/stderr only — never write logs to files inside the container

## .dockerignore
```
.git
.gitignore
node_modules
*.log
.env
.env.*
dist
build
coverage
.nyc_output
**/*.test.*
**/*.spec.*
docs
README.md
```
