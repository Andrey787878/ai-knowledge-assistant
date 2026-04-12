# firewall

Роль для настройки host firewall (UFW) на k3s VM в этапе bootstrap.

## Структура роли

```text
.
├── README.md
├── defaults/main.yml
└── tasks/
    ├── main.yml
    ├── validate.yml
    ├── ufw.yml
    └── verify.yml
```

## Что делает

- Проверяет поддерживаемую ОС (`Debian` family).
- Валидирует базовые firewall-параметры и CIDR-списки.
- Устанавливает `ufw`.
- Применяет default policies:
  - incoming: `deny`
  - outgoing: `allow`
- Разрешает TCP-порты по source CIDR:
  - `22` из `firewall_admin_ssh_sources`
  - `6443` из `kube_api_allowed_cidrs`
  - `80` из `edge_http_cidrs`
  - `443` из `edge_allowed_client_cidrs`
- Включает UFW.
- Проверяет:
  - `Status: active`
  - default policies
  - наличие правил для `22/6443/80/443`.

## Граница ответственности

Роль управляет только host firewall на VM.

Роль не управляет cloud security groups и не настраивает k3s.

## Переменные

Основные переменные из `defaults/main.yml`:

- `firewall_package` - пакет firewall (по умолчанию `ufw`).
- `firewall_default_incoming_policy` - default incoming policy.
- `firewall_default_outgoing_policy` - default outgoing policy.
- `firewall_admin_ssh_sources` - CIDR-ы для `22/tcp`.
- `kube_api_allowed_cidrs` - CIDR-ы для `6443/tcp`.
- `edge_http_cidrs` - CIDR-ы для `80/tcp`.
- `edge_allowed_client_cidrs` - CIDR-ы для `443/tcp`.
- `firewall_apt_*` - apt таймауты/ретраи.

Значения CIDR должны задаваться в
`inventories/cloud/group_vars/all/zz-local.yml` (или через vault overrides).

## Использование

```yaml
- hosts: k3s_hosts
  become: true
  roles:
    - firewall
```

## Быстрая проверка

```bash
cd deploy/kubernetes/bootstrap
ansible -i inventories/cloud/hosts.yml k3s_hosts -b -m command -a "ufw status verbose"
```
