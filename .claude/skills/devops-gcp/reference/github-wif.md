# GitHub Actions → GCP with Workload Identity Federation

Look up the immutable IDs once: `gh api repos/ORG/REPO --jq '.owner.id, .id'`.

## Pool, provider and deploy service account

```hcl
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"

  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.repository_id"       = "assertion.repository_id"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    "attribute.environment"         = "assertion.environment"
    "attribute.ref"                 = "assertion.ref"
  }

  # Immutable numeric IDs (as strings) — names can be re-registered by someone else.
  attribute_condition = <<-EOT
    assertion.repository_owner_id == '${var.github_owner_id}' &&
    assertion.repository_id == '${var.github_repository_id}'
  EOT

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "deploy" {
  account_id   = "gha-deploy-${var.environment}"
  display_name = "GitHub Actions deploy (${var.environment})"
}

# Only jobs running in the matching GitHub environment can impersonate this SA.
resource "google_service_account_iam_member" "deploy_wif" {
  service_account_id = google_service_account.deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.environment/${var.environment}"
}

resource "google_project_iam_member" "deploy_run" {
  project = var.project_id
  role    = "roles/run.developer"
  member  = google_service_account.deploy.member
}

resource "google_artifact_registry_repository_iam_member" "deploy_push" {
  location   = google_artifact_registry_repository.app.location
  repository = google_artifact_registry_repository.app.name
  role       = "roles/artifactregistry.writer"
  member     = google_service_account.deploy.member
}

# actAs only on the runtime SA the service uses — not project-wide.
resource "google_service_account_iam_member" "deploy_act_as_runtime" {
  service_account_id = google_service_account.api.name
  role               = "roles/iam.serviceAccountUser"
  member             = google_service_account.deploy.member
}
```

- The `attribute.environment` binding relies on the provider condition to restrict the
  repository; never bind `attribute.environment` in a pool shared across repositories without it.
- Direct resource access (`principalSet://…` granted roles without a service account) also works
  for most APIs; a service account keeps the audit trail and blast radius simpler for deploys.

## Workflow (build, push by digest, deploy)

```yaml
name: cd-gcp
on:
  push:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: deploy-production
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-24.04
    environment: production
    permissions:
      contents: read
      id-token: write
    env:
      IMAGE: ${{ vars.GCP_REGION }}-docker.pkg.dev/${{ vars.GCP_PROJECT_ID }}/app/api
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      - id: auth
        uses: google-github-actions/auth@7c6bc770dae815cd3e89ee6cdf493a5fab2cc093 # v3.0.0
        with:
          workload_identity_provider: ${{ vars.GCP_WIF_PROVIDER }}
          service_account: ${{ vars.GCP_DEPLOY_SA }}

      - uses: google-github-actions/setup-gcloud@aa5489c8933f4cc7a4f7d45035b3b1440c9c10db # v3.0.1

      - run: gcloud auth configure-docker "${{ vars.GCP_REGION }}-docker.pkg.dev" --quiet

      - uses: docker/setup-buildx-action@f87e5991a6d7451dcb8d9637bfbc97413f497069 # v4.4.1

      - id: build
        uses: docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc # v7.4.0
        with:
          context: .
          push: true
          tags: ${{ env.IMAGE }}:${{ github.sha }}
          provenance: mode=max
          sbom: true

      - name: Run migrations
        run: >
          gcloud run jobs deploy api-migrate
          --image="${IMAGE}@${{ steps.build.outputs.digest }}"
          --region="${{ vars.GCP_REGION }}"
          --execute-now --wait

      - uses: google-github-actions/deploy-cloudrun@2028e2d7d30a78c6910e0632e48dd561b064884d # v3.0.1
        with:
          service: api
          region: ${{ vars.GCP_REGION }}
          image: ${{ env.IMAGE }}@${{ steps.build.outputs.digest }}
```

- `vars.*` are non-secret identifiers; there are no GCP secrets in GitHub at all.
- Use a separate job (and GitHub environment) per target environment; the WIF binding for
  `production` rejects tokens from other environments.
- The `api-migrate` job's service account must be one the deploy SA can `actAs`; grant
  `roles/iam.serviceAccountUser` on that SA too.
