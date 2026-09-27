# Ansible recipes

## Layout

```
ansible/
├── ansible.cfg
├── collections/requirements.yml     # pinned collection versions
├── inventory/
│   ├── production/
│   │   ├── hosts.yml
│   │   └── group_vars/
│   │       ├── all.yml
│   │       └── all.vault.yml         # ansible-vault encrypted
│   └── staging/
├── playbooks/
│   ├── site.yml
│   ├── k3s.yml
│   └── deploy-app.yml
└── roles/
    ├── hardening/
    ├── k3s/
    └── app_compose/
        ├── defaults/main.yml
        ├── handlers/main.yml
        ├── tasks/main.yml
        ├── templates/
        └── molecule/default/
```

`ansible.cfg`:

```ini
[defaults]
inventory = inventory/staging
roles_path = roles
collections_path = collections
host_key_checking = True
forks = 20
stdout_callback = default
result_format = yaml

[ssh_connection]
pipelining = True
```

## Inventory

```yaml
# inventory/production/hosts.yml
all:
  children:
    k3s_servers:
      hosts:
        k3s-srv-1.example.internal:
        k3s-srv-2.example.internal:
        k3s-srv-3.example.internal:
    k3s_agents:
      hosts:
        k3s-agt-[1:6].example.internal:
    app_vms:
      hosts:
        app-[1:3].example.internal:
  vars:
    ansible_user: deploy
```

## Hardening role (excerpt)

```yaml
# roles/hardening/tasks/main.yml
- name: Install security updates tooling
  ansible.builtin.apt:
    name: [unattended-upgrades, nftables, auditd]
    state: present
    update_cache: true
    cache_valid_time: 3600
  become: true

- name: Harden sshd
  ansible.builtin.template:
    src: sshd_hardening.conf.j2
    dest: /etc/ssh/sshd_config.d/10-hardening.conf
    owner: root
    group: root
    mode: "0600"
    validate: /usr/sbin/sshd -t -f %s
  become: true
  notify: Restart sshd

- name: Apply kernel parameters required by k3s protect-kernel-defaults
  ansible.posix.sysctl:
    name: "{{ item.key }}"
    value: "{{ item.value }}"
    sysctl_file: /etc/sysctl.d/90-kubelet.conf
    state: present
  loop: "{{ hardening_kubelet_sysctls | dict2items }}"
  become: true
```

`sshd_hardening.conf.j2` sets `PermitRootLogin no`, `PasswordAuthentication no`,
`KbdInteractiveAuthentication no`, `AllowGroups ssh-users`.

## Secrets in playbooks

```yaml
- name: Write app environment file
  ansible.builtin.template:
    src: app.env.j2
    dest: /etc/app/app.env
    owner: root
    group: app
    mode: "0640"
  vars:
    app_db_password: "{{ lookup('community.hashi_vault.vault_kv2_get', 'app/db', engine_mount_point='kv').secret.password }}"
  no_log: true
  become: true
```

- The `community.hashi_vault` collection works against OpenBao's Vault-compatible API; set
  `VAULT_ADDR` and authenticate with AppRole or JWT (CI OIDC) — no static tokens in files.
- For `ansible-vault` files, CI supplies the password through `--vault-password-file` pointing
  at a script that reads a CI secret.

## Quality gates

```bash
ansible-galaxy collection install -r collections/requirements.yml
ansible-lint --profile production
ansible-playbook -i inventory/staging playbooks/site.yml --check --diff
molecule test -s default        # per role, Docker/Podman driver
```

- Pin every collection (`version: "==x.y.z"`) and ansible-core in the CI image.
- Rolling changes use `serial` and `max_fail_percentage: 0`; drain Kubernetes nodes
  (`kubernetes.core.k8s_drain`) before reboots.
