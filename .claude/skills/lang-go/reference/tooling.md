# Go tooling configuration

Read when creating or changing `go.mod`, `.golangci.yml`, or the Go CI job.

## go.mod

```
module example.com/orders

go 1.27

toolchain go1.27.1

tool golang.org/x/vuln/cmd/govulncheck
```

- Add tools with `go get -tool <pkg>`; run them with `go tool <name>`. Tool versions are pinned in
  `go.mod`/`go.sum` like any dependency.
- Libraries set `go` to the oldest supported release (currently `go 1.26`) and avoid APIs newer
  than that; `go test` runs the `stdversion` vet check by default on 1.27 and flags violations.

## .golangci.yml (golangci-lint v2)

```yaml
version: "2"

linters:
  default: standard        # errcheck, govet, ineffassign, staticcheck, unused
  enable:
    - bodyclose
    - errorlint
    - gosec
    - noctx
    - sloglint
  settings:
    errcheck:
      check-type-assertions: true
    sloglint:
      attr-only: true
      key-naming-case: snake
  exclusions:
    generated: strict
    rules:
      - path: _test\.go
        linters:
          - gosec

formatters:
  enable:
    - gofmt
    - goimports
  settings:
    goimports:
      local-prefixes:
        - example.com/orders
```

- Migrate a v1 config with `golangci-lint migrate`; v2 has no default exclusions, so expect new
  findings on the first run.
- `golangci-lint fmt` applies the formatters; `golangci-lint run` also reports unformatted files.

## CI job

```bash
go mod download
go mod tidy -diff
golangci-lint run ./...
go vet ./...
go test -race -shuffle=on -coverprofile=coverage.out ./...
go tool govulncheck ./...
```

- Install golangci-lint from its release binary or the official GitHub Action at a pinned version;
  pin third-party actions by commit SHA.
- Run short fuzz sessions on changed fuzz targets (`go test -run=^$ -fuzz=FuzzParseAmount
  -fuzztime=30s ./internal/money`) and commit new failing inputs from `testdata/fuzz/`.
- After a Go upgrade, run `go fix ./...` and review the modernizer diff in its own PR.
