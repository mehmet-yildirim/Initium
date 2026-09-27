# Delivery, registry, logging and backup recipes

## Ephemeral runners: Actions Runner Controller scale sets

```bash
helm install arc oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
  --version 0.14.2 --namespace arc-systems --create-namespace

helm install onprem-runners oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --version 0.14.2 --namespace arc-runners --create-namespace \
  --values runner-values.yaml
```

```yaml
# runner-values.yaml
githubConfigUrl: https://github.com/my-org
githubConfigSecret: arc-github-app   # GitHub App credentials, synced by External Secrets
minRunners: 0
maxRunners: 10
runnerGroup: onprem-deploy           # restrict which repositories may use these runners
containerMode:
  type: kubernetes                   # job containers as pods; no privileged Docker-in-Docker
  kubernetesModeWorkVolumeClaim:
    accessModes: ["ReadWriteOnce"]
    storageClassName: fast-local
    resources:
      requests:
        storage: 10Gi
```

- Workflows target the scale set by installation name: `runs-on: onprem-runners`.
- Every job gets a fresh pod that is deleted afterwards; build images with rootless BuildKit or
  Kaniko-style builders instead of mounting a Docker socket.
- Run runners in a cluster (or at least namespace + NetworkPolicy) separate from production
  workloads; they need egress to GitHub and Harbor only.
- Use a GitHub App (not a PAT) and a runner group limited to the repositories that deploy on-prem.

## Harbor

- Install with the `harbor/harbor` chart 1.19.x (Harbor 2.15), `existingSecretAdminPassword`,
  external PostgreSQL (CloudNativePG) and S3-compatible storage for blobs.
- Per project: vulnerability scanning on push (Trivy), prevent pulling images with critical
  CVEs, tag immutability rules for release tags, retention rules for CI tags.
- Robot accounts per pipeline with push to one project only; rotate via the API and store in
  OpenBao.
- Proxy-cache projects for Docker Hub, ghcr.io and quay.io so clusters never pull from the
  internet directly; set k3s `registries.yaml` mirrors to Harbor.
- Cosign signatures and SBOM attestations are stored as OCI artifacts next to the image;
  replicate them together to the DR Harbor.

## VM deploy by digest (Compose + systemd, via Ansible)

```yaml
# playbooks/deploy-app.yml
- name: Deploy app to VMs
  hosts: app_vms
  serial: 1
  max_fail_percentage: 0
  become: true
  vars:
    app_image: "harbor.example.internal/app/api@{{ app_image_digest }}"
  tasks:
    - name: Fail if the digest is not pinned
      ansible.builtin.assert:
        that: app_image_digest is match('^sha256:[a-f0-9]{64}$')

    - name: Render compose file
      ansible.builtin.template:
        src: compose.yaml.j2
        dest: /opt/app/compose.yaml
        owner: root
        group: root
        mode: "0644"

    - name: Pull and start
      community.docker.docker_compose_v2:
        project_src: /opt/app
        pull: always
        state: present
        wait: true
        wait_timeout: 120

    - name: Health check
      ansible.builtin.uri:
        url: "http://127.0.0.1:8080/healthz"
        status_code: 200
      register: health
      retries: 10
      delay: 3
      until: health.status == 200
```

Run from an ephemeral runner with
`ansible-playbook -i inventory/production playbooks/deploy-app.yml -e app_image_digest=sha256:…`.

## Grafana Alloy (replaces Promtail)

Kubernetes: `grafana/alloy` chart with a config like below (plus `loki.source.kubernetes` for pod
logs). VMs: the `alloy` package managed by Ansible. Example for journald on hosts:

```alloy
loki.source.journal "system" {
  forward_to = [loki.write.default.receiver]
  labels     = { job = "journal", host = constants.hostname }
}

loki.write "default" {
  endpoint {
    url = "https://loki.example.internal/loki/api/v1/push"

    basic_auth {
      username      = "alloy"
      password_file = "/etc/alloy/loki-password"   // 0600, rendered from OpenBao
    }
  }
}
```

- Migrate existing Promtail configs with `alloy convert --source-format=promtail`.
- Collector hardening (memory limits, no `0.0.0.0` listeners) follows `devops-observability`.

## Velero

```bash
velero install --provider aws --plugins velero/velero-plugin-for-aws:<pinned> \
  --bucket velero-prod --secret-file ./credentials-velero \
  --backup-location-config region=us-east-1,s3ForcePathStyle=true,s3Url=https://s3.backup.example.internal \
  --use-node-agent

velero schedule create daily --schedule="0 3 * * *" --ttl 720h --snapshot-move-data
```

- Delete the local credentials file after install; the Secret lives in the `velero` namespace.
- Target bucket has object lock / versioning and lives outside the cluster's failure domain.
- Exclude namespaces whose data is backed up natively (CloudNativePG clusters) to avoid
  inconsistent volume copies.
