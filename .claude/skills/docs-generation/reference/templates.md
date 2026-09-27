# README, CHANGELOG and ADR templates

## README.md

```markdown
# project-name

One sentence: what it does and for whom.

[![CI](https://github.com/org/project-name/actions/workflows/ci.yml/badge.svg)](https://github.com/org/project-name/actions/workflows/ci.yml)

## Quick start

    git clone https://github.com/org/project-name.git
    cd project-name
    cp .env.example .env        # fill in placeholders; never commit .env
    npm ci && npm run dev

## Usage

Minimal, copy-pasteable example of the main use case.

## Configuration

| Variable | Required | Default | Description |
|---|---|---|---|
| `DATABASE_URL` | yes | — | Postgres connection string |

## Documentation

- [Tutorials](docs/tutorials/) · [How-to guides](docs/how-to/) · [Reference](docs/reference/) · [Architecture](docs/explanation/)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security issues: [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
```

## CHANGELOG.md (Keep a Changelog)

```markdown
# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Export orders as CSV from the orders page (#412).

## [1.4.0] - 2026-09-27

### Changed
- `GET /orders` now paginates with cursors; `page` is ignored (#398).

### Deprecated
- `GET /orders?page=` will be removed in 2.0.0.

### Security
- Upgrade `libxml2` to fix CVE-2026-XXXXX in the import worker.

[Unreleased]: https://github.com/org/project-name/compare/v1.4.0...HEAD
[1.4.0]: https://github.com/org/project-name/compare/v1.3.2...v1.4.0
```

Allowed headings: `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`.

## ADR (MADR 4.0 minimal)

File: `docs/adr/0007-use-postgresql-for-order-storage.md`

```markdown
---
status: accepted            # proposed | accepted | rejected | deprecated | superseded by ADR-0012
date: 2026-09-27
decision-makers: [platform-team]
---

# Use PostgreSQL for order storage

## Context and Problem Statement

Orders need transactional writes across order, payment and inventory records, and ad-hoc
reporting queries. Which primary data store do we use?

## Decision Drivers

- ACID transactions across aggregates
- Team familiarity and managed-service availability
- Reporting without a separate warehouse for the first year

## Considered Options

- PostgreSQL 18 (managed)
- DynamoDB
- MongoDB Atlas

## Decision Outcome

Chosen option: "PostgreSQL 18 (managed)", because it is the only option meeting the transaction
requirement without application-level sagas.

### Consequences

- Good, because reporting queries run on a read replica with plain SQL.
- Bad, because horizontal write scaling requires partitioning later.
```
