# Secrets: OpenBao / Vault and External Secrets

## OpenBao on Kubernetes (HA, Raft storage)

```bash
helm repo add openbao https://openbao.github.io/openbao-helm
helm install openbao openbao/openbao --version 0.29.6 \
  --namespace openbao --create-namespace \
  --values openbao-values.yaml
```

```yaml
# openbao-values.yaml
server:
  ha:
    enabled: true
    replicas: 3
    raft:
      enabled: true
  dataStorage:
    size: 20Gi
  auditStorage:
    enabled: true
injector:
  enabled: false        # External Secrets Operator is the default delivery path
```

- Terminate TLS on OpenBao itself (cert-manager `Certificate` mounted into the pods); never run
  the listener with `tls_disable` outside a lab.
- Configure auto-unseal (PKCS#11 HSM, cloud KMS, or transit seal on a separate cluster);
  initialize once with split recovery keys held by separate people.
- Manage mounts, policies and auth roles as code (Terraform `hashicorp/vault` provider works
  against OpenBao), not by hand.
- Existing HashiCorp Vault installs keep working with the same patterns; check the BSL terms
  before offering Vault as part of a hosted product.

## Kubernetes auth + policy for External Secrets

```hcl
path "kv/data/app/*" {
  capabilities = ["read"]
}
```

```bash
bao auth enable kubernetes
bao write auth/kubernetes/config kubernetes_host="https://kubernetes.default.svc"
bao policy write app-read app-read.hcl
bao write auth/kubernetes/role/eso-app \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=app-read ttl=15m
```

## External Secrets Operator

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: openbao
spec:
  provider:
    vault:                       # OpenBao uses the Vault-compatible provider
      server: https://openbao.openbao.svc:8200
      path: kv
      version: v2
      caProvider:
        type: ConfigMap
        name: openbao-ca
        namespace: openbao
        key: ca.crt
      auth:
        kubernetes:
          mountPath: kubernetes
          role: eso-app
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: app-db
  namespace: app
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: openbao
  target:
    name: app-db
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: app/db
        property: password
```

Restrict which namespaces may use a `ClusterSecretStore` with `spec.conditions` (namespace
selectors) or use namespaced `SecretStore`s per team.

## Chart credentials via `existingSecret`

```yaml
# kube-prometheus-stack values
grafana:
  admin:
    existingSecret: grafana-admin     # synced by an ExternalSecret
    userKey: admin-user
    passwordKey: admin-password
```

- Same pattern for Harbor (`existingSecretAdminPassword`), Bitnami-style charts
  (`auth.existingSecret`) and CloudNativePG (`bootstrap.initdb.secret`).
- Never pass secrets with `helm --set` or commit them to values files.
