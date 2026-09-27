---
name: devops-onprem
description: On-premise and bare-metal deployment standards — k3s or kubeadm clusters with pinned versions, Traefik or Envoy Gateway via Gateway API, MetalLB, Ansible (ansible-core 2.21) host automation and hardening, OpenBao or Vault with External Secrets, PostgreSQL 18 via CloudNativePG or Patroni with pgBackRest/WAL-G, Harbor, ephemeral self-hosted runners, GitOps deploy by digest, Grafana Alloy, and Velero/etcd backups. Use when provisioning or operating self-hosted clusters, VMs, Ansible playbooks, or inventories.
globs:
  - "**/ansible/**"
  - "**/playbooks/**"
  - "**/inventory/**"
alwaysApply: false
---
<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->

# On-Premise Deployment Standards

Self-hosted infrastructure: hosts, clusters, and the platform services a cloud would otherwise
provide. Manifests, Helm charts, Gateway routes, Kyverno policies and GitOps apps follow
`devops-kubernetes`; pipelines follow `devops-cicd`; telemetry follows `devops-observability`;
container images follow `devops-docker`.

## Baseline and toolchain (September 2026)

- Kubernetes 1.35–1.37 supported upstream; run k3s `v1.37.x+k3s1` or `v1.36.x+k3s1` pinned by
  exact version, never the moving `stable` channel in production.
- ansible-core 2.21 with collections pinned in `requirements.yml`; ansible-lint and Molecule in CI.
- Platform services: MetalLB 0.16 (chart), cert-manager 1.21 (OCI chart), External Secrets
  Operator 2.11, OpenBao 2.7, Harbor 2.15, CloudNativePG 1.30 with Barman Cloud plugin 0.15,
  Grafana Alloy 1.20, Velero 1.18, ARC `gha-runner-scale-set` 0.14.
- Hosts: a supported LTS distribution (Ubuntu 24.04/26.04, RHEL 9/10, Debian 13) with
  unattended security updates and a documented reboot window.

## Platform choice

| Need | Use |
|---|---|
| Edge, small clusters, 1–7 nodes, low ops headcount | k3s (embedded etcd HA with 3 servers) |
| Large clusters, strict upstream parity, custom CNI/CRI | kubeadm (or Rancher RKE2 for CIS defaults) |
| A few services on VMs, no Kubernetes skills | Docker Compose + systemd, managed by Ansible |
| Stateful databases with dedicated DBAs | VMs with Patroni + pgBackRest |

- Do not start new work on Docker Swarm or ingress-nginx (retired March 2026).
- Everything is declared: Ansible for hosts, GitOps for cluster contents, Terraform for anything
  with an API (vSphere, Proxmox, DNS, firewalls) — see `devops-terraform`.

## k3s clusters

- Install from a versioned config file (`/etc/rancher/k3s/config.yaml`), not long flag lists —
  a comment after a line-continuation `\` silently truncates the command.
- Keep the kubeconfig at its default `0600` root-only mode; copy it for admins with
  `install -m 600` and prefer OIDC/SSO kubeconfigs for humans. Never `write-kubeconfig-mode: 644`.
- Enable `secrets-encryption`, `protect-kernel-defaults`, scheduled etcd snapshots to off-cluster
  S3, and a join token read from a file.
- Keep the bundled Traefik v3 and enable its Kubernetes Gateway provider with a
  `HelmChartConfig`; new routes use `HTTPRoute`. Migrate existing Ingress objects with
  `ingress2gateway`.
- Disable `servicelb` only when MetalLB provides `LoadBalancer` addresses.
- Upgrade with the system-upgrade-controller `Plan`s, one minor at a time, servers before agents.
- On kubeadm clusters use Envoy Gateway (or Cilium/Istio) as the Gateway implementation.

Read `reference/k3s-cluster.md` when installing or upgrading k3s, MetalLB, Traefik Gateway API,
or cert-manager.

## Ansible

- Layout: `inventory/<env>/`, `playbooks/`, `roles/`, `collections/requirements.yml`; one role
  per concern, variables in `group_vars`/`host_vars`, defaults in `roles/*/defaults`.
- FQCN modules only (`ansible.builtin.apt`), `become` per task or play rather than globally,
  idempotent tasks (`changed_when`/`creates`), `no_log: true` on anything touching secrets.
- Secrets come from OpenBao/Vault lookups or `ansible-vault`-encrypted files; the vault password
  comes from a script or CI secret, never a file in the repo.
- CI runs `ansible-lint`, `ansible-playbook --check --diff` against staging, and Molecule
  scenarios for each role.

Read `reference/ansible.md` when writing roles, inventories, or host hardening.

## Secrets

- Licensing: HashiCorp Vault is BSL 1.1; OpenBao is the MPL-2.0 Linux Foundation fork with a
  compatible API. Default to OpenBao for new installs unless you need Vault Enterprise features
  or already run Vault.
- Applications receive secrets as Kubernetes Secrets synced by External Secrets Operator from
  OpenBao/Vault (Kubernetes auth), or via the agent injector where file rotation is needed.
- Helm charts reference credentials with `existingSecret`-style values; never `--set password=…`
  (it lands in shell history, CI logs and the Helm release secret).
- Auto-unseal with an HSM/KMS or transit seal; unseal keys and root token are split and offline.

Read `reference/secrets.md` when deploying OpenBao/Vault, External Secrets, or chart credentials.

## Databases

- PostgreSQL 18 for new clusters (17 acceptable).
- On Kubernetes: CloudNativePG with the Barman Cloud plugin (`ObjectStore` CRD) for WAL archiving
  and base backups — the in-tree `barmanObjectStore` is deprecated and removed in 1.31.
- On VMs: Patroni (etcd/Consul DCS) with pgBackRest or WAL-G to object storage, encrypted and
  with retention; HAProxy or PgBouncer in front.
- Measure restores, not backups: monthly automated restore to a scratch cluster with PITR.

Read `reference/postgres.md` when writing CloudNativePG clusters or Patroni/pgBackRest config.

## Delivery

- Cluster contents are reconciled by Argo CD or Flux (see `devops-kubernetes`); CI builds, pushes
  to Harbor, and commits the new digest — it never holds cluster credentials.
- Self-hosted runners are ephemeral: ARC runner scale sets in a dedicated cluster/namespace, or
  one-shot VMs. No persistent runners with shared Docker sockets.
- Harbor: projects per team, robot accounts per pipeline, Trivy scanning, immutable tag rules,
  proxy-cache projects for upstream registries, replication to a DR site.
- Deploy by digest everywhere; verify cosign signatures at admission (Kyverno
  `ImageValidatingPolicy`, defined in `devops-kubernetes`).
- VM deploys: Ansible pulls `image@sha256:…` and restarts the systemd/Compose unit with health
  checks and serial batches (`serial: 1`, `max_fail_percentage: 0`).

Read `reference/delivery.md` when setting up runners, Harbor, VM deploys, or backups.

## Networking and TLS

- MetalLB in L2 mode for flat networks, BGP when routers support it; dedicated address pools
  per environment.
- cert-manager with an ACME issuer (DNS-01 for internal names) or an internal CA issuer
  (step-ca, OpenBao PKI); certificates on Gateway listeners.
- Default-deny host firewalls (nftables/firewalld via Ansible) and Kubernetes NetworkPolicies.

## Security

- CIS benchmark baseline on hosts (Ansible hardening role) and clusters (k3s hardening guide,
  `kube-bench` in CI against staging).
- SSH: keys or SSH certificates only, no root login, no passwords; bastion or VPN for access.
- Pod Security Standards `restricted` on app namespaces; admission policies from
  `devops-kubernetes`.
- Air-gapped sites mirror images into Harbor and verify signatures before import.
- Audit logs from API server, OpenBao and hosts ship to central storage with retention.

## Observability

- kube-prometheus-stack for metrics and alerts; Grafana admin credentials from
  `admin.existingSecret`.
- Grafana Alloy for logs (Promtail reached end of life on 2026-03-02), metrics and OTLP
  forwarding to Loki/Mimir/Tempo or another backend. Convert Promtail configs with
  `alloy convert --source-format=promtail`.
- node_exporter and Alloy on non-Kubernetes hosts too; alert on disk, certificate expiry,
  etcd snapshot age and backup age.

## Backup and DR

- Velero with CSI snapshots and file-system backup to off-site S3-compatible storage
  (object-lock enabled); etcd snapshots on a separate schedule.
- Documented RTO/RPO per service; quarterly full restore drill into an empty cluster.

## Testing

- Molecule for roles, `ansible-lint` and `yamllint` on every PR.
- Provision a throwaway k3s cluster (k3d or VMs) in CI to validate platform upgrades before
  production.
- Restore tests for Velero and database backups are scheduled jobs with alerts on failure.

_Versions verified September 2026._
