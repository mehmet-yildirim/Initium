# GitHub Actions reference workflows

All actions are pinned to the commit SHA of the release named in the comment (resolved from the
upstream repositories in September 2026). Let Dependabot/Renovate move them forward.

## ci.yml — pull request checks

```yaml
name: ci

on:
  pull_request:
  push:
    branches: [main]

permissions: {}

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  verify:
    runs-on: ubuntu-24.04
    timeout-minutes: 15
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: actions/setup-node@820762786026740c76f36085b0efc47a31fe5020 # v7.0.0
        with:
          node-version-file: .nvmrc
          cache: npm
      - run: npm ci
      - run: npm run lint
      - run: npm run typecheck
      - run: npm test -- --coverage   # thresholds enforced in vitest.config.ts
      - run: npm audit --audit-level=high

  workflow-lint:
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: actionlint
        uses: docker://rhysd/actionlint@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667 # 1.7.12
        with:
          args: -color
      - name: zizmor
        uses: zizmorcore/zizmor-action@cc914d7f3750a2d13d75c7f184a1060aa0e9d482 # v0.6.4
        with:
          advanced-security: false
          min-severity: medium
```

With GitHub Advanced Security, drop `advanced-security: false` and grant the job
`security-events: write` so findings land in code scanning.

## release-image.yml — build, attest, sign, verify, deploy

```yaml
name: release-image

on:
  push:
    branches: [main]

permissions: {}

concurrency:
  group: release-image
  cancel-in-progress: false

env:
  # GHCR requires a lowercase repository path; set it explicitly.
  IMAGE: ghcr.io/acme/app

jobs:
  build:
    runs-on: ubuntu-24.04
    timeout-minutes: 30
    permissions:
      contents: read
      packages: write
      id-token: write          # Sigstore certificate for attest and cosign
      attestations: write
      artifact-metadata: write
    outputs:
      digest: ${{ steps.build.outputs.digest }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: docker/setup-buildx-action@f87e5991a6d7451dcb8d9637bfbc97413f497069 # v4.4.1
      - uses: docker/login-action@dbcb813823bdd20940b903addbd779551569679f # v4.6.0
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - id: meta
        uses: docker/metadata-action@dc802804100637a589fabce1cb79ff13a1411302 # v6.2.0
        with:
          images: ${{ env.IMAGE }}
          tags: type=sha,format=long
      - id: build
        uses: docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc # v7.4.0
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          sbom: true
          provenance: mode=max
          cache-from: type=gha
          cache-to: type=gha,mode=max
      - uses: actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6 # v4.2.2
        with:
          subject-name: ${{ env.IMAGE }}
          subject-digest: ${{ steps.build.outputs.digest }}
          push-to-registry: true
      - uses: sigstore/cosign-installer@6f9f17788090df1f26f669e9d70d6ae9567deba6 # v4.1.2
      - name: Sign image digest
        env:
          DIGEST: ${{ steps.build.outputs.digest }}
        run: cosign sign --yes "${IMAGE}@${DIGEST}"

  deploy-staging:
    needs: build
    runs-on: ubuntu-24.04
    timeout-minutes: 15
    environment: staging
    permissions:
      contents: read
      packages: read
      attestations: read
      id-token: write          # OIDC to the cloud; trust policy pinned to environment:staging
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: docker/login-action@dbcb813823bdd20940b903addbd779551569679f # v4.6.0
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Verify provenance before deploy
        env:
          GH_TOKEN: ${{ github.token }}
          DIGEST: ${{ needs.build.outputs.digest }}
        run: gh attestation verify "oci://${IMAGE}@${DIGEST}" --repo "${GITHUB_REPOSITORY}"
      - uses: aws-actions/configure-aws-credentials@e1253824e5c10ff9df46874f81ed3ec929e19cfd # v6.3.0
        with:
          role-to-assume: ${{ vars.DEPLOY_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}
      - name: Deploy by digest
        env:
          DIGEST: ${{ needs.build.outputs.digest }}
        run: ./scripts/deploy.sh staging "${IMAGE}@${DIGEST}"
```

Notes:

- `deploy-production` is the same job with `environment: production` (required reviewers,
  `main`-only deployment branches) and a trust policy whose `sub` is
  `repo:acme/app:environment:production`.
- With GitOps, replace the deploy step by a commit that updates the image digest in the
  environment overlay; the controller in the cluster applies it (see `devops-kubernetes`).
- Cloud-specific deploy commands (ECS task definitions, Cloud Run, AKS) live in `devops-aws`,
  `devops-gcp`, and `devops-azure`.

## Script injection: wrong vs right

```yaml
# WRONG — PR title is attacker-controlled and is expanded into the shell script
- run: echo "PR title is ${{ github.event.pull_request.title }}"

# RIGHT — pass through the environment and quote it
- env:
    PR_TITLE: ${{ github.event.pull_request.title }}
  run: echo "PR title is ${PR_TITLE}"
```

## Other CI systems

- GitLab CI: pin `include:` templates and component versions by SHA or immutable tag, use
  `id_tokens:` for OIDC, protected environments and protected variables, and `rules:` instead of
  `only/except`.
- Jenkins: declarative pipelines, credentials binding (never `echo`), ephemeral Kubernetes agents,
  pinned shared-library versions.
- Azure Pipelines: workload identity federation service connections, environment approvals and
  checks, templates referenced at a pinned `ref`.
