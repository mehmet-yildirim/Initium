# GitOps, routing, and secrets

## Kustomize overlay pinning the digest

```yaml
# k8s/overlays/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: app-production
resources:
  - ../../base
  - external-secret.yaml
  - httproute.yaml
images:
  - name: ghcr.io/acme/app
    digest: sha256:0000000000000000000000000000000000000000000000000000000000000000
```

CI (or Renovate) updates only the `digest:` line in a PR; the GitOps controller applies it after
merge.

## Argo CD Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-production
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: acme-apps                       # AppProject restricts source repos and destinations
  source:
    repoURL: https://github.com/acme/deploy.git
    targetRevision: main
    path: k8s/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: app-production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
```

## Flux equivalent

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: deploy
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/acme/deploy.git
  ref:
    branch: main
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: app-production
  namespace: flux-system
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: deploy
  path: ./k8s/overlays/production
  prune: true
  wait: true
  timeout: 5m
```

## Gateway API: shared Gateway and an app route

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: public
  namespace: gateway-system
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-dns
spec:
  gatewayClassName: envoy-gateway          # name depends on the installed implementation
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      hostname: "*.example.com"
      tls:
        mode: Terminate
        certificateRefs:
          - name: wildcard-example-com-tls
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchLabels:
              gateway-access: public
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app
  namespace: app-production
spec:
  parentRefs:
    - name: public
      namespace: gateway-system
      sectionName: https
  hostnames:
    - app.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: app
          port: 80
```

Migrating from Ingress NGINX: run `ingress2gateway` against existing Ingress objects, review every
translated annotation (snippets and rewrites rarely map one-to-one), run both paths in parallel,
and cut over DNS gradually.

## External Secrets Operator

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: app-db
  namespace: app-production
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: cloud-secrets                    # configured per cloud with workload identity
  target:
    name: app-db
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: prod/app/db
        property: password
```

The `ClusterSecretStore` authenticates with workload identity (IRSA/EKS Pod Identity, GKE Workload
Identity, AKS Workload Identity) — configuration lives in the cloud skills. Restrict which
namespaces may use it with `spec.conditions`.
