---
name: devops-onprem
description: On-premise deployment standards — Kubernetes (kubeadm/k3s), Docker Swarm, Ansible, HashiCorp Vault, Nginx/HAProxy, Harbor, Prometheus/Grafana, TLS automation. Use when deploying to self-hosted Kubernetes, VMs, or on-premise infrastructure.
paths:
  - "**/k8s/**/*.yaml"
  - "**/kubernetes/**/*.yaml"
  - "**/helm/**"
  - "**/ansible/**"
  - "**/playbooks/**"
  - "**/Vagrantfile"
  - "**/roles/**/*.yml"
  - "**/inventory/**"
  - "**/docker-compose*.yml"
  - "**/nginx/**"
  - "**/haproxy/**"
---

# On-Premise Deployment Standards

## Infrastructure Options

| Option | Best for | Complexity | HA capable |
|---|---|---|---|
| **k3s** | Small clusters (< 10 nodes), edge, dev/staging | Low | Yes (HA mode) |
| **kubeadm** | Production clusters, standard Kubernetes | Medium | Yes |
| **Docker Swarm** | Simple containerized workloads, small teams | Low | Yes |
| **Ansible + systemd** | Non-containerized workloads, legacy apps | Medium | Manual |
| **Nomad** | Mixed workloads (containers + VMs + binaries) | Medium | Yes |

---

## Kubernetes On-Premise (k3s — recommended for new deployments)

### Installation
```bash
# Single-node install (dev/staging)
curl -sfL https://get.k3s.io | sh -s - \
  --write-kubeconfig-mode 644 \
  --disable traefik \          # We'll use Nginx ingress instead
  --disable servicelb           # We'll use MetalLB

# HA install — first server node
curl -sfL https://get.k3s.io | sh -s - server \
  --cluster-init \
  --token "${K3S_TOKEN}" \
  --tls-san "${LOAD_BALANCER_IP}"

# Additional server nodes (quorum: 3 or 5 total)
curl -sfL https://get.k3s.io | sh -s - server \
  --server "https://${FIRST_SERVER_IP}:6443" \
  --token "${K3S_TOKEN}"

# Worker nodes
curl -sfL https://get.k3s.io | K3S_URL="https://${SERVER_IP}:6443" K3S_TOKEN="${K3S_TOKEN}" sh -
```

### Namespace structure
```
namespaces/
├── production        # Production workloads
├── staging           # Staging workloads
├── monitoring        # Prometheus, Grafana, AlertManager
├── ingress           # Nginx ingress controller
├── cert-manager      # TLS certificate automation
└── vault             # HashiCorp Vault
```

### Standard Kubernetes manifests
```yaml
# k8s/production/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: production
  labels:
    app: myapp
    version: v1.2.3
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0   # Zero-downtime — wait for new pod before terminating old
  selector:
    matchLabels: { app: myapp }
  template:
    metadata:
      labels: { app: myapp, version: v1.2.3 }
    spec:
      # Spread across nodes for HA
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels: { app: myapp }

      containers:
        - name: myapp
          image: registry.mycompany.internal/myapp:v1.2.3
          ports: [{ containerPort: 3000 }]

          resources:
            requests: { cpu: 250m, memory: 256Mi }
            limits:   { cpu: 1000m, memory: 512Mi }

          envFrom:
            - configMapRef: { name: myapp-config }

          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: myapp-secrets
                  key: database-url

          livenessProbe:
            httpGet: { path: /health/live, port: 3000 }
            initialDelaySeconds: 30
            periodSeconds: 30

          readinessProbe:
            httpGet: { path: /health/ready, port: 3000 }
            initialDelaySeconds: 10
            periodSeconds: 10

          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep 15"]  # Drain connections before termination

      terminationGracePeriodSeconds: 60
```

```yaml
# k8s/production/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: production
spec:
  selector: { app: myapp }
  ports: [{ port: 80, targetPort: 3000 }]
---
# k8s/production/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"  # or internal CA
spec:
  ingressClassName: nginx
  tls:
    - hosts: [myapp.mycompany.internal]
      secretName: myapp-tls
  rules:
    - host: myapp.mycompany.internal
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service: { name: myapp, port: { number: 80 } }
```

### Horizontal Pod Autoscaler
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: myapp
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target: { type: Utilization, averageUtilization: 70 }
    - type: Resource
      resource:
        name: memory
        target: { type: Utilization, averageUtilization: 80 }
```

---

## Load Balancing (MetalLB + Nginx Ingress)

```yaml
# MetalLB — provides LoadBalancer services on bare metal
# Install: kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14/config/manifests/metallb-native.yaml

apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: production-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.1.200-192.168.1.210   # Reserved IP range for load balancer VIPs
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: production
  namespace: metallb-system
spec:
  ipAddressPools: [production-pool]
```

```bash
# Nginx Ingress Controller — the single entry point for all HTTP(S) traffic
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress \
  --create-namespace \
  --set controller.service.loadBalancerIP=192.168.1.200
```

---

## TLS Certificate Automation

```bash
# cert-manager — automates Let's Encrypt or internal CA certificates
helm upgrade --install cert-manager cert-manager \
  --repo https://charts.jetstack.io \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true
```

```yaml
# For internal / air-gapped environments — use internal CA
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: internal-ca
spec:
  ca:
    secretName: internal-ca-key-pair   # Pre-created from your CA cert+key

# For internet-accessible hosts — use Let's Encrypt
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ops@mycompany.com
    privateKeySecretRef: { name: letsencrypt-prod }
    solvers:
      - http01:
          ingress: { class: nginx }
```

---

## Secrets Management (HashiCorp Vault)

```bash
# Install Vault on Kubernetes
helm upgrade --install vault vault \
  --repo https://helm.releases.hashicorp.com \
  --namespace vault \
  --create-namespace \
  --set "server.ha.enabled=true" \
  --set "server.ha.replicas=3" \
  --set "injector.enabled=true"   # Vault Agent Injector — sidecars that inject secrets
```

```yaml
# Use Vault Agent Injector to inject secrets as files at runtime
# Annotate your pod to inject secrets
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: production
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "myapp-production"
        vault.hashicorp.com/agent-inject-secret-database-url: "secret/data/production/myapp/database"
        vault.hashicorp.com/agent-inject-template-database-url: |
          {{- with secret "secret/data/production/myapp/database" -}}
          {{ .Data.data.url }}
          {{- end }}
```

```hcl
# Vault policy
path "secret/data/production/myapp/*" {
  capabilities = ["read"]
}

# Kubernetes auth method — pods authenticate using their service account token
resource "vault_kubernetes_auth_backend_role" "myapp_production" {
  backend                          = "kubernetes"
  role_name                        = "myapp-production"
  bound_service_account_names      = ["myapp"]
  bound_service_account_namespaces = ["production"]
  token_ttl                        = 3600
  token_policies                   = ["myapp-production"]
}
```

---

## Automation (Ansible)

### Playbook structure
```
ansible/
├── inventories/
│   ├── production/
│   │   ├── hosts.yml        # Production server list
│   │   └── group_vars/
│   │       ├── all.yml      # Variables for all hosts
│   │       └── k3s.yml      # Variables for k3s nodes
│   └── staging/
│       └── hosts.yml
├── roles/
│   ├── common/              # Base OS hardening, NTP, users
│   ├── docker/              # Docker CE installation
│   ├── k3s-server/          # k3s server setup
│   ├── k3s-agent/           # k3s agent setup
│   ├── postgresql/          # PostgreSQL installation + config
│   └── monitoring/          # Node Exporter, Promtail
├── site.yml                 # Main playbook
└── requirements.yml         # Ansible Galaxy dependencies
```

```yaml
# inventories/production/hosts.yml
all:
  children:
    k3s_server:
      hosts:
        node1: { ansible_host: 192.168.1.10 }
        node2: { ansible_host: 192.168.1.11 }
        node3: { ansible_host: 192.168.1.12 }
    k3s_agent:
      hosts:
        worker1: { ansible_host: 192.168.1.20 }
        worker2: { ansible_host: 192.168.1.21 }
    postgresql:
      hosts:
        db-primary:   { ansible_host: 192.168.1.30 }
        db-replica:   { ansible_host: 192.168.1.31 }
```

```yaml
# roles/common/tasks/main.yml — base hardening
- name: Disable root SSH login
  lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^PermitRootLogin'
    line: 'PermitRootLogin no'
  notify: restart sshd

- name: Configure unattended upgrades for security patches
  package: name=unattended-upgrades state=present

- name: Set up NTP synchronization
  package: name=chrony state=present

- name: Enable UFW firewall
  ufw: state=enabled policy=deny

- name: Allow SSH
  ufw: rule=allow port=22 proto=tcp

- name: Allow k3s API server
  ufw: rule=allow port=6443 proto=tcp
  when: "'k3s_server' in group_names"
```

---

## Private Container Registry (Harbor)

```bash
# Install Harbor — enterprise container registry with vulnerability scanning
helm upgrade --install harbor harbor \
  --repo https://helm.goharbor.io \
  --namespace registry \
  --create-namespace \
  --set expose.type=ingress \
  --set expose.ingress.hosts.core=registry.mycompany.internal \
  --set expose.tls.certSource=secret \
  --set expose.tls.secret.secretName=harbor-tls \
  --set externalURL=https://registry.mycompany.internal \
  --set persistence.persistentVolumeClaim.registry.size=100Gi \
  --set trivy.enabled=true   # Built-in vulnerability scanning
```

```yaml
# Configure Docker daemon to trust internal registry
# /etc/docker/daemon.json (on all nodes)
{
  "insecure-registries": [],
  "registry-mirrors": [],
  "log-driver": "json-file",
  "log-opts": { "max-size": "100m", "max-file": "3" }
}
```

---

## PostgreSQL On-Premise (Ansible-managed)

```yaml
# roles/postgresql/tasks/main.yml
- name: Install PostgreSQL 15
  package:
    name: [postgresql-15, postgresql-client-15, python3-psycopg2]
    state: present

- name: Configure postgresql.conf
  template:
    src: postgresql.conf.j2
    dest: /etc/postgresql/15/main/postgresql.conf
  notify: restart postgresql

- name: Configure pg_hba.conf (authentication)
  template:
    src: pg_hba.conf.j2
    dest: /etc/postgresql/15/main/pg_hba.conf
  notify: reload postgresql
```

```ini
# templates/postgresql.conf.j2
listen_addresses = '*'
max_connections  = 200
shared_buffers   = {{ (ansible_memtotal_mb * 0.25) | int }}MB
work_mem         = 4MB
wal_level        = replica
max_wal_senders  = 3
archive_mode     = on
archive_command  = 'test ! -f /var/lib/postgresql/wal_archive/%f && cp %p /var/lib/postgresql/wal_archive/%f'
log_checkpoints  = on
log_connections  = on
log_line_prefix  = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
```

### Streaming replication (primary → replica)
```yaml
# On primary: create replication user
- name: Create replication user
  postgresql_user:
    name: replicator
    password: "{{ vault_replication_password }}"
    role_attr_flags: REPLICATION

# On replica: configure recovery
- name: Configure standby
  template:
    src: standby.signal.j2
    dest: /var/lib/postgresql/15/main/standby.signal
```

---

## CI/CD for On-Premise (GitHub Actions → Self-Hosted Runner)

```yaml
# .github/workflows/cd-onprem.yml
name: Deploy to On-Premise

on:
  push:
    tags: ["v*"]

jobs:
  deploy:
    runs-on: self-hosted    # Runs on your own server — no cloud credentials needed
    environment: production

    steps:
      - uses: actions/checkout@v4

      - name: Build and push to Harbor
        run: |
          IMAGE_URI="registry.mycompany.internal/myapp/myapp:${{ github.sha }}"
          docker build -t "$IMAGE_URI" .
          docker push "$IMAGE_URI"
          echo "IMAGE_URI=$IMAGE_URI" >> $GITHUB_ENV

      - name: Deploy to Kubernetes
        run: |
          kubectl set image deployment/myapp \
            myapp="$IMAGE_URI" \
            -n production
          kubectl rollout status deployment/myapp -n production --timeout=5m
```

```bash
# Install GitHub Actions self-hosted runner on a dedicated server
# See: https://docs.github.com/en/actions/hosting-your-own-runners
# The runner communicates outbound only (to api.github.com) — no inbound ports required
./config.sh --url https://github.com/org/repo --token "${RUNNER_TOKEN}"
./run.sh  # or install as a systemd service
```

---

## Monitoring (Prometheus + Grafana)

```bash
# Install kube-prometheus-stack (Prometheus + Grafana + AlertManager + node-exporter)
helm upgrade --install monitoring kube-prometheus-stack \
  --repo https://prometheus-community.github.io/helm-charts \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword="${GRAFANA_PASSWORD}" \
  --set grafana.ingress.enabled=true \
  --set grafana.ingress.hosts[0]=grafana.mycompany.internal \
  --set alertmanager.config.global.slack_api_url="${SLACK_WEBHOOK}"
```

```yaml
# Application ServiceMonitor — tells Prometheus to scrape your app's /metrics endpoint
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myapp
  namespace: production
spec:
  selector:
    matchLabels: { app: myapp }
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
```

---

## Backup Strategy

```bash
# Velero — Kubernetes backup and disaster recovery
helm upgrade --install velero velero \
  --repo https://vmware-tanzu.github.io/helm-charts \
  --namespace velero \
  --create-namespace \
  --set configuration.backupStorageLocation[0].provider=aws \
  --set configuration.backupStorageLocation[0].config.s3Url=https://minio.mycompany.internal \
  --set configuration.backupStorageLocation[0].config.region=us-east-1 \
  --set configuration.backupStorageLocation[0].bucket=k8s-backups

# Daily backup schedule
cat <<EOF | kubectl apply -f -
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: daily-backup
  namespace: velero
spec:
  schedule: "0 3 * * *"    # Daily at 3 AM
  template:
    includedNamespaces: [production]
    ttl: 720h               # 30 days retention
EOF
```

---

## Security Checklist

- [ ] All cluster nodes access via bastion host or VPN — no direct SSH from internet
- [ ] Kubernetes API server not exposed to internet (use kubectl via VPN or bastion)
- [ ] Network policies applied — pods cannot communicate freely across namespaces
- [ ] Pod Security Standards enforced: `restricted` profile for production workloads
- [ ] RBAC: service accounts follow least privilege; no `cluster-admin` for application pods
- [ ] Secrets managed by Vault — no plaintext Kubernetes Secrets for sensitive values
- [ ] All communications TLS-encrypted: ingress → service → pod
- [ ] Image pull policy: `Always` for production to prevent stale images
- [ ] Harbor with Trivy enabled — fail deployment if CRITICAL CVEs in image
- [ ] Audit logging enabled in Kubernetes API server
- [ ] Regular `kubectl get events -A` monitoring and alerting on Warning events
- [ ] etcd encrypted at rest and backed up daily
