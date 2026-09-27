# Docs hooks and CI

## Local hooks (versioned)

`.git/hooks` is not versioned; use lefthook or pre-commit so every contributor runs the same
checks.

```yaml
# lefthook.yml
pre-commit:
  parallel: true
  jobs:
    - name: markdownlint
      glob: "*.md"
      run: npx markdownlint-cli2 {staged_files}
    - name: vale
      glob: "*.{md,mdx}"
      run: vale --minAlertLevel=error {staged_files}
```

```yaml
# .pre-commit-config.yaml (alternative); pin rev to a release tag or SHA
repos:
  - repo: https://github.com/DavidAnson/markdownlint-cli2
    rev: v0.23.3
    hooks:
      - id: markdownlint-cli2
```

Verify `rev` values against upstream releases when adding hooks; update them with
`pre-commit autoupdate` or Renovate.

## Vale

```ini
# .vale.ini
StylesPath = .vale/styles
MinAlertLevel = suggestion
Packages = Microsoft
Vocab = Project

[*.{md,mdx}]
BasedOnStyles = Vale, Microsoft
```

- Run `vale sync` in CI to fetch packages; commit `.vale/styles/config/vocabularies/Project/`
  (`accept.txt`, `reject.txt`) for product terms.

## GitHub Actions workflow

Pin third-party actions to a full commit SHA (resolve the SHA for the release you choose; the
comment records the version). Keep `permissions` minimal.

```yaml
name: docs
on:
  pull_request:
    paths: ["docs/**", "**/*.md", "openapi*.yaml"]
permissions: {}
jobs:
  lint:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - run: npx --yes markdownlint-cli2 "**/*.md" "#node_modules"
      - uses: vale-cli/vale-action@518a9136acc6e6668ce7c00d367051e0941e87ff # v3.0.0
        with:
          fail_level: error
      - uses: lycheeverse/lychee-action@e7477775783ea5526144ba13e8db5eec57747ce8 # v2.9.0
        with:
          args: --offline --no-progress "docs/**/*.md" "*.md"
          fail: true
      - run: npx --yes @redocly/cli lint openapi.yaml
```

- Run a full external link check (drop `--offline`) on a nightly schedule and open an issue on
  failure instead of blocking PRs on third-party outages.
- Build the docs site in the same workflow and upload a preview artifact or deploy a PR preview.

## Docs-impact check

Add to the PR template:

```markdown
- [ ] Docs updated (README / docs/ / OpenAPI / CHANGELOG), or
- [ ] No docs impact — reason:
```
