# Compose dev stack (app + PostgreSQL 18)

Local development only. Ports bind to loopback, the database password is a Compose secret, and
source changes reach the container through `develop.watch` instead of a repo-wide bind mount.

```yaml
# compose.yaml
services:
  app:
    build:
      context: .
      target: build            # stage with dev dependencies (see dockerfile-node.md)
    command: ["npm", "run", "dev"]
    environment:
      NODE_ENV: development
      DATABASE_HOST: postgres
      DATABASE_NAME: app
      DATABASE_USER: app
      DATABASE_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_password
    ports:
      - "127.0.0.1:3000:3000"
    depends_on:
      postgres:
        condition: service_healthy
    develop:
      watch:
        - action: sync
          path: ./src
          target: /app/src
        - action: rebuild
          path: package-lock.json

  postgres:
    image: postgres:18
    environment:
      POSTGRES_USER: app
      POSTGRES_DB: app
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_password
    ports:
      - "127.0.0.1:5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql   # 18+: PGDATA is /var/lib/postgresql/18/docker
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app -d app"]
      interval: 10s
      timeout: 5s
      retries: 5

secrets:
  db_password:
    file: ./secrets/db_password.txt         # gitignored; generate locally

volumes:
  postgres_data:
```

Usage:

- `docker compose up --watch` starts the stack and syncs `./src` on change; lockfile changes
  trigger an image rebuild.
- `docker compose up --wait` (CI/integration tests) blocks until health checks pass.
- The app reads the password from the file named in `DATABASE_PASSWORD_FILE` — support `*_FILE`
  variables in the config loader so the same code works with Kubernetes secret volumes.
- Upgrading from a pre-18 volume: `pg_dumpall` from the old container, start 18 on a new named
  volume (for example `postgres18_data`), restore. Do not point 18 at the old volume.
- Keep production-only concerns (TLS termination, replicas, resource limits) out of this file;
  they belong to the orchestrator.
