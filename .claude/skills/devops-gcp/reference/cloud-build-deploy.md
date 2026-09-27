# Cloud Build and Cloud Deploy recipes

## cloudbuild.yaml (private pool, user-managed SA, provenance)

```yaml
serviceAccount: projects/my-project/serviceAccounts/build-api@my-project.iam.gserviceaccount.com
options:
  logging: CLOUD_LOGGING_ONLY          # required with a user-specified serviceAccount
  requestedVerifyOption: VERIFIED      # SLSA build provenance for images listed below
  pool:
    name: projects/my-project/locations/europe-west1/workerPools/private
substitutions:
  _IMAGE: europe-west1-docker.pkg.dev/my-project/app/api
steps:
  - id: test
    name: gcr.io/cloud-builders/docker@sha256:<pinned-digest>
    args: [build, --target, test, .]
  - id: build
    name: gcr.io/cloud-builders/docker@sha256:<pinned-digest>
    args: [build, -t, "${_IMAGE}:${SHORT_SHA}", .]
images:
  - "${_IMAGE}:${SHORT_SHA}"
```

- Resolve builder digests with `gcloud artifacts docker images describe IMAGE:TAG` and refresh
  them via Renovate; never run floating `:latest` builders.
- The build SA needs only `roles/artifactregistry.writer` on the repository and
  `roles/logging.logWriter`; add `roles/clouddeploy.releaser` if the build creates releases.
- Triggers: GitHub App connection (Cloud Build repositories 2nd gen), `includedFiles` filters,
  and approval required for triggers on untrusted branches or forks.
- Provenance is generated only for images in `images:` (pushed after steps finish). Create the
  Cloud Deploy release from a follow-up trigger or from GitHub Actions using the pushed digest.

## clouddeploy.yaml (pipeline + targets)

```yaml
apiVersion: deploy.cloud.google.com/v1
kind: DeliveryPipeline
metadata:
  name: api
serialPipeline:
  stages:
    - targetId: staging
      profiles: [staging]
    - targetId: production
      profiles: [production]
      strategy:
        canary:
          runtimeConfig:
            cloudRun:
              automaticTrafficControl: true
          canaryDeployment:
            percentages: [10, 50]
            verify: true
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: staging
run:
  location: projects/my-project-staging/locations/europe-west1
executionConfigs:
  - usages: [RENDER, DEPLOY, VERIFY]
    serviceAccount: deploy-exec@my-project-staging.iam.gserviceaccount.com
---
apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
  name: production
requireApproval: true
run:
  location: projects/my-project-prod/locations/europe-west1
executionConfigs:
  - usages: [RENDER, DEPLOY, VERIFY]
    serviceAccount: deploy-exec@my-project-prod.iam.gserviceaccount.com
```

Register with `gcloud deploy apply --file=clouddeploy.yaml --region=europe-west1`, then create a
release per build:

```bash
gcloud deploy releases create "rel-${SHORT_SHA}" \
  --delivery-pipeline=api \
  --region=europe-west1 \
  --images="api=europe-west1-docker.pkg.dev/my-project/app/api@sha256:${DIGEST}"
```

- The Skaffold config next to `clouddeploy.yaml` defines `staging`/`production` profiles, each
  pointing at a Cloud Run service manifest whose image is the placeholder `api`; Cloud Deploy
  substitutes the digest at render time. Pin Skaffold with `--skaffold-version` (≥ 2.17 for
  worker pools).
- `verify: true` runs the Skaffold `verify` container against the canary before promotion.
- Execution SAs per target project hold `roles/run.developer` there and `actAs` on the runtime SA
  only. Approvers get `roles/clouddeploy.approver` on the production target.
- Roll back with `gcloud deploy targets rollback production --delivery-pipeline=api`.
