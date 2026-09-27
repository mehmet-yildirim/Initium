# Dependency update and intake policy

## Dependabot (`.github/dependabot.yml`)

```yaml
version: 2
updates:
  - package-ecosystem: npm
    directory: /
    schedule:
      interval: weekly
    open-pull-requests-limit: 10
    cooldown:
      default-days: 3
      semver-patch-days: 3
      semver-minor-days: 7
      semver-major-days: 30
    groups:
      dev-dependencies:
        dependency-type: development
        update-types: [minor, patch]

  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
    cooldown:
      default-days: 7
    groups:
      actions:
        patterns: ["*"]

  - package-ecosystem: docker
    directory: /
    schedule:
      interval: weekly
    cooldown:
      default-days: 3
```

- `cooldown` accepts 1–90 days; `include`/`exclude` lists (max 150 items) scope it to packages.
- Since July 2026 version updates get a 3-day cooldown by default; security updates always bypass
  cooldown. Set it explicitly anyway so the policy is visible in review.
- Dependabot updates SHA-pinned actions and their trailing version comment together.

## Renovate (`renovate.json`)

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:best-practices"],
  "minimumReleaseAge": "3 days",
  "minimumReleaseAgeBehaviour": "timestamp-required",
  "packageRules": [
    {
      "matchUpdateTypes": ["major"],
      "minimumReleaseAge": "30 days",
      "dependencyDashboardApproval": true
    },
    {
      "matchManagers": ["github-actions"],
      "minimumReleaseAge": "7 days"
    }
  ]
}
```

- `config:best-practices` includes `config:recommended`, `docker:pinDigests`,
  `helpers:pinGitHubActionDigests`, and (Renovate 42+) `security:minimumReleaseAgeNpm`.
- `timestamp-required` holds updates whose registry doesn't report a release timestamp instead of
  merging them immediately.
- Validate with `npx --yes --package renovate -- renovate-config-validator` in CI.

## Package-manager release-age gates

Bots only control PRs; developers running `install` locally need the gate too.

| Tool | Setting | Unit |
|---|---|---|
| npm ≥11.10 | `.npmrc`: `min-release-age=3` | days |
| pnpm ≥10.16 | `pnpm-workspace.yaml`: `minimumReleaseAge: 4320` (pnpm 11 defaults to 1440) | minutes |
| Yarn ≥4.10 | `.yarnrc.yml`: `npmMinimalAgeGate: 4320`; ≥4.15 accepts `"3d"` and defaults to 1 day | minutes |
| uv ≥0.9.17 | `[tool.uv]`: `exclude-newer = "3 days"` (per package: `exclude-newer-package`) | duration |
| Bun | `bunfig.toml` `[install]`: `minimumReleaseAge = 259200` | seconds |

Use the tool's exclusion list for your own org's packages so internal releases aren't delayed.

## Install scripts

```ini
# .npmrc
ignore-scripts=true
min-release-age=3
```

- With `ignore-scripts`, run required builds explicitly (`npm rebuild <pkg>`) for an allowlist.
- pnpm blocks dependency build scripts by default; approve per package (`pnpm approve-builds`).

## Adding a new dependency

1. Prefer the standard library or an existing dependency.
2. Check: repository link matches the package, active maintainers, release history, weekly
   downloads, open security advisories (osv.dev), OpenSSF Scorecard score, provenance.
3. Check the license against the allowlist.
4. Pin via lockfile; record why it was added in the PR description.

## License compliance

```yaml
# .github/workflows/dependency-review.yml (job excerpt)
permissions:
  contents: read
  pull-requests: write
steps:
  - uses: actions/dependency-review-action@a1d282b36b6f3519aa1f3fc636f609c47dddb294 # v5.0.0
    with:
      fail-on-severity: high
      allow-licenses: MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC, MPL-2.0
      comment-summary-in-pr: on-failure
```

- Maintain the allowlist with legal; copyleft (GPL, AGPL) in distributed or network-served
  proprietary code needs explicit approval.
- Ship third-party notices generated from the SBOM with each release.
