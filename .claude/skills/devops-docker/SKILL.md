---
name: devops-docker
description: Container image and Compose standards — BuildKit Dockerfiles (`# syntax=docker/dockerfile:1`, cache and secret mounts), multi-stage builds on Node 24 LTS, distroless or Docker Hardened Images, `docker buildx bake`, SBOM and SLSA provenance attestations, cosign signing, deploy by digest, and Compose v5 with `develop.watch` and secrets. Use when writing or reviewing Dockerfiles, Containerfiles, compose files, bake files, .dockerignore, or container build/runtime configuration.
paths:
  - "**/Dockerfile*"
  - "**/*.dockerfile"
  - "**/Containerfile*"
  - "**/compose*.y*ml"
  - "**/docker-compose*.y*ml"
  - "**/docker-bake.hcl"
  - "**/.dockerignore"
---

# Docker & Container Standards

Image build, supply chain, and local Compose. CI wiring (build-push, attest, verify) is in
`devops-cicd`; cluster runtime (probes, resources, admission) is in `devops-kubernetes`.

## Baseline (September 2026)

- Docker Engine with BuildKit (default builder) and Buildx 0.37; Compose 5.5.
- Every Dockerfile starts with `# syntax=docker/dockerfile:1` to get the current stable frontend
  (secret/cache mounts, `--check` build checks, heredocs).
- Node images: `node:24-slim` for build stages (Node 24 is Active LTS; move to 26 after it enters
  LTS on 2026-10-28). Runtime: `gcr.io/distroless/nodejs24-debian13:nonroot` or a Docker Hardened
  Image.
- PostgreSQL for local dev: `postgres:18` (19 is still in beta). Postgres 18+ images moved
  `PGDATA` to `/var/lib/postgresql/18/docker` and the `VOLUME` to `/var/lib/postgresql` — mount
  the volume at `/var/lib/postgresql`. Do not reuse a pre-18 volume; dump and restore.

## Toolchain

- Lint Dockerfiles with Hadolint and `docker build --check` (BuildKit build checks) in CI.
- Scan images with Trivy, Grype, or Docker Scout; fail on fixable HIGH/CRITICAL. Pin the scanner
  itself (image by digest, action by SHA) — see `devops-cicd` for the 2026 Trivy compromise.
- Define multi-image or multi-platform builds in `docker-bake.hcl` and run `docker buildx bake`
  locally and in CI so both use the same definition.

## Base images

- Prefer, in order: distroless (`gcr.io/distroless/*-debian13:nonroot`), Docker Hardened Images
  (DHI), then official `-slim`. Alpine only when musl is verified to work for all native deps.
- Docker Hardened Images: the Community catalog is free and Apache 2.0 since Dec 2025, pulled from
  `dhi.io` after `docker login dhi.io` (use an organization access token in CI). DHI Enterprise is
  paid (SLA-backed CVE fixes, FIPS/STIG variants). Chainguard Images are an alternative.
- Pin production bases by digest: `FROM node:24-slim@sha256:<digest>`; let Renovate or Dependabot
  bump digests. Never `latest`.
- Distroless has no shell, `wget`, or `curl`. Health checks must use the runtime itself
  (`/nodejs/bin/node dist/healthcheck.js`) or be left to the orchestrator's probes.

## Dockerfile rules

- Multi-stage: separate `deps` (production deps only), `build` (all deps + compile), and `runtime`
  (artifacts only). Never copy the build stage's `node_modules` into the runtime.
- Install with the lockfile: `npm ci` (npm has no `--frozen-lockfile`; that is Yarn/pnpm).
  Production deps: `npm ci --omit=dev` in the deps stage.
- Cache package managers with `RUN --mount=type=cache,target=/root/.npm` (or the pnpm/pip/go
  equivalent) instead of baking caches into layers.
- Build-time secrets (private registry tokens) only via
  `RUN --mount=type=secret,id=npm_token,env=NPM_TOKEN ...` and
  `docker buildx build --secret id=npm_token,env=NPM_TOKEN`. Never `ARG`/`ENV` for secrets —
  they persist in image history.
- Order layers from least to most frequently changing; copy manifests before sources.
- Use exec-form `ENTRYPOINT`/`CMD` so the app is PID 1 and receives `SIGTERM`; handle it and
  drain within the orchestrator's grace period.
- Run as non-root with a numeric UID (`nonroot` = 65532 in distroless); no `sudo`, no setuid.
- Add OCI labels (`org.opencontainers.image.source`, `.revision`, `.version`) — the metadata action
  in CI sets them automatically.
- Keep `.dockerignore` strict: `.git`, `node_modules`, `.env*`, `dist`, `coverage`, test output.

Read `reference/dockerfile-node.md` when writing a Node.js Dockerfile, `.dockerignore`, or a
distroless health check.

## Build, tag, and release

- Build with Buildx and attach attestations: `--sbom=true --provenance=mode=max` (or `attest` in
  bake). Attestations are stored in the registry next to the image.
- Tag immutably: `<image>:<git-sha>` for every build, plus `<image>:v1.2.3` for releases. Never
  overwrite a tag; enable tag immutability in the registry where supported.
- Deploy by digest (`<image>@sha256:...`), never by tag. Promote the same digest through
  environments — never rebuild per environment.
- Sign the pushed digest with cosign keyless (`cosign sign --yes <image>@sha256:...`; cosign v3
  writes the Sigstore bundle as an OCI referrer). Cosign warns when given a tag — always sign the
  digest.
- Multi-platform (`linux/amd64,linux/arm64`) for images that run on Graviton/Ampere or Apple
  silicon dev machines.

Read `reference/bake.md` when writing `docker-bake.hcl` or configuring multi-platform builds,
attestations, and registry caches.

## Compose (local development)

- Compose is for local dev and tests, not production orchestration.
- Publish ports on loopback only: `"127.0.0.1:5432:5432"`. A bare `"5432:5432"` exposes the
  database on every host interface.
- Sensitive values via top-level `secrets:` mounted at `/run/secrets/<name>`, consumed with
  `*_FILE` variables (`POSTGRES_PASSWORD_FILE`). `.env`/`env_file` only for non-secret config;
  never commit `.env`.
- Use `develop.watch` (`sync`, `sync+restart`, `rebuild`) for hot reload instead of bind-mounting
  the whole repo over `node_modules`. Run with `docker compose up --watch`.
- `depends_on` with `condition: service_healthy`; healthchecks on every stateful service.
- Named volumes for data; the project network Compose creates is already isolated — add extra
  networks only to separate tiers.

Read `reference/compose.md` for a complete dev stack (app + Postgres 18 with secrets and watch).

## Runtime hardening

- `--read-only` root filesystem with `tmpfs` for writable paths; `--cap-drop=ALL`, add back only
  what is proven necessary; `--security-opt=no-new-privileges`.
- Set memory and CPU limits; in Kubernetes use requests/limits (see `devops-kubernetes`).
- Log to stdout/stderr as structured JSON; never write logs to files in the container.

## Security

- No secrets in layers, build args, labels, or Compose files committed to git.
- Rebuild on base-image updates, not only on code changes; scheduled rebuilds weekly at minimum.
- Registry access: CI pushes with short-lived OIDC credentials; runtime nodes pull read-only.
- Verify signatures and provenance before deploy (CI verify step and cluster admission policy).

## Observability

- Images carry OCI labels linking back to source and commit; SBOMs are queryable per digest
  (`docker buildx imagetools inspect <image>@<digest> --format '{{ json .SBOM }}'`).
- Emit OpenTelemetry from the app; the container only provides stdout logs and exit codes.

## Testing

- Build every Dockerfile in CI on PRs (no push) with `--check` and a vulnerability scan.
- Smoke-test the runtime image: start it, hit the health endpoint, and assert a non-root user
  with `docker inspect --format '{{.Config.User}}' <image>` (distroless has no `id` binary).
- Integration tests use Testcontainers or the Compose stack with `docker compose up --wait`.

_Versions verified September 2026._
