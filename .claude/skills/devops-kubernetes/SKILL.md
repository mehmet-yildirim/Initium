---
name: devops-kubernetes
description: Kubernetes workload and platform standards — version policy (1.35–1.37 supported), Pod Security Standards, resource requests/limits, probes, PDBs, HPA, NetworkPolicy default-deny, least-privilege RBAC, Gateway API 1.6 (ingress-nginx is retired), Helm 4 OCI charts vs Kustomize 5, GitOps with Argo CD 3.5 or Flux 2.9, External Secrets Operator, Kyverno 1.19 CEL policies and ValidatingAdmissionPolicy, cosign image verification, cert-manager 1.21, and deploy by digest. Use when writing or reviewing Kubernetes manifests, Helm charts, Kustomize overlays, helmfiles, GitOps applications, or cluster admission policies.
paths:
  - "**/k8s/**"
  - "**/charts/**"
  - "**/Chart.yaml"
  - "**/kustomization.y*ml"
  - "**/helmfile*.y*ml"
---

# Kubernetes Standards

Cloud-neutral workload, packaging, delivery, and policy rules. Managed-cluster specifics (EKS,
GKE, AKS, k3s/on-prem, cloud IAM for pods) stay in `devops-aws`, `devops-gcp`, `devops-azure`,
and `devops-onprem`; image build rules are in `devops-docker`; CI is in `devops-cicd`.

## Baseline (September 2026)

- Upstream supports 1.37, 1.36, and 1.35 (1.37.0 released 2026-08-26). 1.34 reaches end of life
  on 2026-10-27 — upgrade now. Run a supported minor and stay within one minor of the latest your
  managed provider offers; upgrade at least every six months, one minor at a time.
- Before each upgrade, scan manifests and charts for removed APIs against the target version and
  read the release's "urgent upgrade notes".
- Tooling: kubectl within one minor of the API server, Helm 4.3, Kustomize 5.8, Gateway API 1.6,
  Argo CD 3.5, Flux 2.9, Kyverno 1.19, cert-manager 1.21, External Secrets Operator 2.11.

## Toolchain

- Render then validate in CI: `helm template` / `kustomize build` piped to kubeconform with the
  target Kubernetes version schemas (plus CRD schemas).
- Lint with kube-linter or Trivy config / Checkov; `helm lint --strict` for charts; ship a
  `values.schema.json` with every chart.
- Server-side dry run against a staging cluster (`kubectl apply --dry-run=server`) catches
  admission-policy denials before merge.
- Policy tests: `kyverno test` for Kyverno policies; chart-testing (`ct`) on kind for charts.

## Structure

```
k8s/
├── base/                 # shared manifests or chart values
├── components/           # optional Kustomize components (e.g. otel-sidecar)
└── overlays/
    ├── staging/
    └── production/
charts/<name>/            # first-party Helm charts (Chart.yaml apiVersion v2)
```

- One namespace per application per environment; label everything with
  `app.kubernetes.io/{name,instance,version,component,part-of,managed-by}`.
- Helm for distributable, parameterized packages (third-party software, charts you publish);
  Kustomize for first-party apps with per-environment overlays. Do not template YAML with sed.
- Environment differences live in overlays/values files, not branches.

## Workloads

- Images by digest (`image: ghcr.io/acme/app@sha256:...`); Kustomize `images:` with `digest:`,
  Helm `image.digest` value. Never `latest`; `imagePullPolicy: IfNotPresent` with digests.
- Requests on every container (CPU and memory). Memory limit = memory request. CPU limits are
  optional — omit for latency-sensitive services unless a quota requires them. Namespace
  `ResourceQuota` and `LimitRange` backstop missing values. In-place resize (GA in 1.35) adjusts
  resources without restarts.
- Probes: `startupProbe` for slow boots, `readinessProbe` gates traffic, `livenessProbe` only
  detects deadlock and never checks downstream dependencies.
- Graceful shutdown: handle `SIGTERM`, `preStop: { sleep: { seconds: 5 } }` (GA in 1.34) to let
  endpoints drain, `terminationGracePeriodSeconds` longer than the drain time.
- Availability: at least 2 replicas, `topologySpreadConstraints` across zones and nodes, a
  `PodDisruptionBudget` (`maxUnavailable: 1` or `minAvailable`) for every multi-replica workload.
- Autoscaling: HPA `autoscaling/v2` on CPU or custom/external metrics (metrics-server, KEDA for
  queue depth); never HPA and VPA on the same resource metric.
- Native sidecars (`initContainers` with `restartPolicy: Always`) for proxies and log shippers.
- Config via ConfigMaps; roll pods on change with a content hash (Kustomize generators do this).

Read `reference/workload.md` for a complete hardened Deployment, Service, PDB, HPA, and
NetworkPolicy set.

## Security

- Pod Security Standards: label every namespace `pod-security.kubernetes.io/enforce: restricted`
  (plus `warn`/`audit`); only system namespaces get `baseline`/`privileged`, with justification.
- Container `securityContext`: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`,
  `readOnlyRootFilesystem: true`, `capabilities.drop: [ALL]`, `seccompProfile.type: RuntimeDefault`.
- ServiceAccounts: one per workload, `automountServiceAccountToken: false` unless the app calls
  the API; cloud access via workload identity (see cloud skills), never static keys in Secrets.
- RBAC least privilege: namespaced `Role` over `ClusterRole`; no wildcards in `verbs`/`resources`;
  no `cluster-admin` bindings for humans or CI; humans get read-only by default and break-glass
  elevation that is audited.
- NetworkPolicy: default-deny ingress and egress per namespace, then allow DNS and explicit
  dependencies. Requires a CNI that enforces policy (Cilium, Calico).
- Secrets: External Secrets Operator (`external-secrets.io/v1`) syncing from the cloud secret
  manager or OpenBao/Vault; never commit Secret manifests (SOPS or Sealed Secrets only as a
  fallback). Enable etcd encryption at rest. Never pass secrets with `helm --set` (they persist in
  release history); reference an `existingSecret`.
- Admission policy as code:
  - Built-in `ValidatingAdmissionPolicy` (GA 1.30) and `MutatingAdmissionPolicy` (GA 1.36) for
    simple CEL rules without webhooks.
  - Kyverno 1.19 with the CEL policy types (`ValidatingPolicy`, `MutatingPolicy`,
    `ImageValidatingPolicy`, `policies.kyverno.io/v1`). `ClusterPolicy`/`Policy` are deprecated
    and removed in 1.20 — do not write new ones; migrate existing ones.
  - Verify image signatures at admission: Kyverno `ImageValidatingPolicy` with a keyless cosign
    attestor pinned to your release workflow identity; start in `Audit`, then `Deny`.

Read `reference/policies.md` for namespace PSS labels, a ValidatingAdmissionPolicy, and a Kyverno
image-signature policy.

## Traffic and TLS

- Ingress NGINX was retired in March 2026 and receives no security fixes. New work uses Gateway
  API (`gateway.networking.k8s.io/v1`: `GatewayClass`, `Gateway`, `HTTPRoute`, `GRPCRoute`);
  migrate existing Ingress objects with `ingress2gateway` and verify annotations by hand.
- Implementations: Envoy Gateway, Istio, Cilium, NGINX Gateway Fabric, Traefik, or the cloud
  provider's Gateway controller. Platform team owns `Gateway`; app teams own routes
  (`allowedRoutes` by namespace label).
- cert-manager 1.21 from the OCI chart (`oci://quay.io/jetstack/charts/cert-manager`,
  `crds.enabled=true`; `installCRDs` is deprecated) with ACME DNS-01 or an internal CA; enable
  its Gateway API support so `Gateway` listeners get certificates.

## Delivery (GitOps)

- Pull-based GitOps with Argo CD or Flux: the cluster reconciles from Git/OCI; CI never holds
  cluster-admin credentials or runs `kubectl apply` against production.
- CI builds, signs, and attests the image, then opens a PR (or commits) that bumps the digest in
  the environment overlay; Renovate, Flux image automation, or Argo CD Image Updater can automate
  staging bumps. Production promotion is a reviewed PR.
- Enable automated sync with prune and self-heal for app namespaces; drift is reverted, not
  hand-fixed. Use sync waves/dependencies for CRDs before CRs.
- Helm 4: install charts from OCI registries pinned by version or digest
  (`oci://registry/charts/app@sha256:...`). New installs use server-side apply; releases created by
  Helm 3 keep client-side apply until you pass `--server-side`.
- Progressive delivery for risky services: Argo Rollouts or Flagger canaries with metric
  analysis (see `devops-cicd`).

Read `reference/gitops.md` for an Argo CD Application, Flux equivalent, HTTPRoute, and
ExternalSecret.

## Observability

- metrics-server for HPA; kube-state-metrics and node metrics scraped by Prometheus or the
  OpenTelemetry Collector (`otelcol-k8s` DaemonSet with `k8sattributes`); see
  `devops-observability`.
- Enable API server audit logging and ship it off-cluster; alert on RBAC changes, exec into pods,
  and admission-policy denials.
- Apps log JSON to stdout; no log files in containers.

## Testing

- Every PR: render, kubeconform against the target version, lint, policy tests.
- Chart and overlay changes deploy to an ephemeral kind or staging namespace with smoke tests.
- Upgrade rehearsal: run the next Kubernetes minor in staging for at least one release cycle
  before production.
- Game days: node drain, zone loss, and PDB behaviour are exercised, not assumed.

_Versions verified September 2026._
