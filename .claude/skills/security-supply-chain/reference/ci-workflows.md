# Supply-chain CI workflows

Actions are pinned to the full commit SHA of the release named in the comment (verified
September 2026); Dependabot/Renovate update both. Workflow-level `permissions: {}` denies
everything; each job grants only what it needs.

## Build, SBOM, sign and attest a container image

```yaml
name: release-image
on:
  push:
    tags: ["v*"]
permissions: {}
jobs:
  build:
    runs-on: ubuntu-latest
    environment: release
    permissions:
      contents: read
      packages: write        # push to GHCR
      id-token: write        # OIDC for cosign keyless and attestations
      attestations: write
    env:
      IMAGE: ghcr.io/${{ github.repository }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: docker/login-action@dbcb813823bdd20940b903addbd779551569679f # v4.6.0
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - id: push
        uses: docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc # v7.4.0
        with:
          push: true
          tags: ${{ env.IMAGE }}:${{ github.ref_name }}
      - uses: anchore/sbom-action@3ad7283483fc7af8ff2b4ea19663c2d5ca935e26 # v0.24.2
        with:
          image: ${{ env.IMAGE }}@${{ steps.push.outputs.digest }}
          format: cyclonedx-json
          output-file: sbom.cdx.json
      - uses: sigstore/cosign-installer@6f9f17788090df1f26f669e9d70d6ae9567deba6 # v4.1.2
      - run: cosign sign --yes "${IMAGE}@${DIGEST}"
        env:
          DIGEST: ${{ steps.push.outputs.digest }}
      - uses: actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6 # v4.2.2
        with:
          subject-name: ${{ env.IMAGE }}
          subject-digest: ${{ steps.push.outputs.digest }}
          push-to-registry: true
      - uses: actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6 # v4.2.2
        with:
          subject-name: ${{ env.IMAGE }}
          subject-digest: ${{ steps.push.outputs.digest }}
          sbom-path: sbom.cdx.json
          push-to-registry: true
```

- Pass expressions through `env:` rather than interpolating `${{ }}` into `run:` scripts
  (prevents script injection from attacker-controlled values).
- Sign and attest the digest output by the build step, never a re-resolved tag.

## Verify before deploy

```bash
cosign verify "ghcr.io/org/app@sha256:<digest>" \
  --certificate-identity "https://github.com/org/app/.github/workflows/release-image.yml@refs/tags/v1.4.0" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

gh attestation verify "oci://ghcr.io/org/app@sha256:<digest>" \
  --repo org/app \
  --signer-workflow org/app/.github/workflows/release-image.yml \
  --deny-self-hosted-runners

cosign verify-blob --bundle app.tar.gz.sigstore.json \
  --certificate-identity-regexp '^https://github.com/org/app/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  app.tar.gz
```

## GoReleaser (v2)

```yaml
version: 2
sboms:
  - artifacts: archive            # Syft must be on PATH
checksum:
  name_template: checksums.txt
signs:
  - cmd: cosign
    signature: "${artifact}.sigstore.json"
    args: ["sign-blob", "--bundle=${signature}", "${artifact}", "--yes"]
    artifacts: checksum           # checksums cover archives and SBOMs
docker_signs:
  - cmd: cosign
    args: ["sign", "${artifact}@${digest}", "--yes"]
```

Run GoReleaser in a job with `id-token: write` so cosign signs keylessly; add `actions/attest`
with `subject-checksums: dist/checksums.txt` for provenance.

## npm trusted publishing

```yaml
jobs:
  publish:
    runs-on: ubuntu-latest       # GitHub-hosted runners only
    environment: npm
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: actions/setup-node@820762786026740c76f36085b0efc47a31fe5020 # v7.0.0
        with:
          node-version: 24
          registry-url: https://registry.npmjs.org
      - run: npm ci
      - run: npm publish --provenance --access public
```

- Configure the trusted publisher (org, repo, workflow file, environment) on npmjs.com, then
  revoke existing automation tokens. Requires npm ≥11.5.1; `package.json` `repository.url` must
  match the GitHub repository exactly.

## PyPI trusted publishing

```yaml
jobs:
  publish:
    runs-on: ubuntu-latest
    environment: pypi
    permissions:
      id-token: write
    steps:
      - uses: actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c # v8.0.1
        with:
          name: dist
          path: dist/
      - uses: pypa/gh-action-pypi-publish@dc37677b2e1c63e2034f94d8a5b11f265b73ba33 # v1.14.2
```

Build in a separate job without `id-token`; publish only downloads the built `dist/`. Must be a
top-level workflow, not a reusable one.

## OpenSSF Scorecard

```yaml
name: scorecard
on:
  branch_protection_rule:
  schedule:
    - cron: "30 1 * * 6"
  push:
    branches: [main]
permissions: read-all
jobs:
  analysis:
    runs-on: ubuntu-latest
    permissions:
      security-events: write
      id-token: write
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: ossf/scorecard-action@2d1146689b8cda280b9bc96326124645441f03bc # v2.4.4
        with:
          results_file: results.sarif
          results_format: sarif
          publish_results: true
      - uses: github/codeql-action/upload-sarif@2892aa5e19bbd11bc0cff5427e3b750a04d9e3c2 # v4.38.2
        with:
          sarif_file: results.sarif
```

## OpenVEX

```bash
vexctl create \
  --product "pkg:oci/app@sha256:<digest>" \
  --vuln CVE-2026-XXXXX \
  --status not_affected \
  --justification vulnerable_code_not_in_execute_path \
  --file app.openvex.json

grype "ghcr.io/org/app@sha256:<digest>" --vex app.openvex.json --fail-on high
```
