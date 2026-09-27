# k3s cluster recipes

Prefer the `k3s.orchestration` Ansible collection (k3s-io/k3s-ansible) for multi-node installs;
the steps below show what it does.

## Server config (first server of an HA cluster)

`/etc/rancher/k3s/config.yaml` (templated by Ansible, mode `0600`):

```yaml
cluster-init: true
token-file: /etc/rancher/k3s/cluster-token   # 0600, generated once, stored in OpenBao
tls-san:
  - k8s-api.example.internal
secrets-encryption: true
protect-kernel-defaults: true
write-kubeconfig-mode: "0600"
disable:
  - servicelb           # only when MetalLB provides LoadBalancer IPs
etcd-snapshot-schedule-cron: "0 */6 * * *"
etcd-snapshot-retention: 28
etcd-s3: true
etcd-s3-endpoint: s3.backup.example.internal
etcd-s3-bucket: k3s-etcd-prod
etcd-s3-config-secret: k3s-etcd-s3   # kube-system Secret with the S3 credentials
kube-apiserver-arg:
  - audit-log-path=/var/lib/rancher/k3s/server/logs/audit.log
  - audit-policy-file=/etc/rancher/k3s/audit-policy.yaml
  - audit-log-maxage=30
```

Install with a pinned version (the script reads the config file):

```bash
curl -sfL https://get.k3s.io -o /tmp/k3s-install.sh
sudo INSTALL_K3S_VERSION="v1.37.0+k3s1" sh /tmp/k3s-install.sh server
```

- Additional servers use the same file with `server: https://k8s-api.example.internal:6443`
  instead of `cluster-init`; run 3 (or 5) servers for etcd quorum.
- Agents: `INSTALL_K3S_VERSION=… K3S_URL=https://k8s-api.example.internal:6443 sh /tmp/k3s-install.sh agent`
  with `token-file` in the agent config.
- `protect-kernel-defaults` requires the sysctls from the k3s CIS hardening guide to be applied
  first (Ansible role).
- Admin access: `sudo install -m 600 -o "$USER" -g "$USER" /etc/rancher/k3s/k3s.yaml ~/.kube/config`
  and replace `127.0.0.1` with the API hostname. Day-to-day users authenticate via OIDC
  (`kube-apiserver-arg: oidc-issuer-url=…`), not the cluster-admin kubeconfig.

## Traefik with Gateway API

`/var/lib/rancher/k3s/server/manifests/traefik-config.yaml`:

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    providers:
      kubernetesGateway:
        enabled: true
      kubernetesIngress:
        enabled: true   # set false once all Ingress objects are migrated
```

- Confirm the Gateway API CRDs are present (`kubectl get crd gateways.gateway.networking.k8s.io`).
  k3s ships them with its Traefik CRD chart; don't apply a different upstream bundle over them.
- Define the `Gateway` and `HTTPRoute`s as in `devops-kubernetes`, with `gatewayClassName: traefik`.
- Convert existing ingress-nginx objects with
  `ingress2gateway print --providers=ingress-nginx --namespace=app` and review the output
  before committing; translate Traefik `IngressRoute`/middleware annotations by hand.

## MetalLB

```bash
helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb --version 0.16.1 \
  --namespace metallb-system --create-namespace
```

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: prod
  namespace: metallb-system
spec:
  addresses:
    - 10.20.30.200-10.20.30.220
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: prod
  namespace: metallb-system
spec:
  ipAddressPools: [prod]
```

## cert-manager (OCI chart, CRDs managed by the chart)

```bash
helm install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.21.2 \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true \
  --set config.apiVersion=controller.config.cert-manager.io/v1alpha1 \
  --set config.kind=ControllerConfiguration \
  --set config.enableGatewayAPI=true
```

In GitOps, pin the same chart version in the Argo CD/Flux source. Issuers: ACME DNS-01 for
internal names, or a `ClusterIssuer` backed by the internal CA (step-ca, OpenBao PKI).

## Upgrades

- Install the system-upgrade-controller and declare `Plan`s pinned to the target version
  (`version: v1.37.1+k3s1`), `concurrency: 1`, `cordon: true`, server plan before agent plan.
- Take an on-demand snapshot first: `k3s etcd-snapshot save --name pre-upgrade`.
- Restore: `k3s server --cluster-reset --cluster-reset-restore-path=<snapshot>` on one server,
  then rejoin the others.
