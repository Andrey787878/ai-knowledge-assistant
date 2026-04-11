# Сеть Ansible-деплоя (4 VM)

## Область

Документ описывает фактическую сетевую модель:

- bastion + ProxyJump,
- host firewall (`firewalld`) с deny-by-default,
- edge HTTPS для внешнего трафика,
- private internal трафик между сервисами,
- cloud-сегментацию `public/private subnet` и NAT egress для private VM.

## Топология

- `postgres` VM: PostgreSQL (`5432/tcp`)
- `ollama` VM: Ollama API (`11434/tcp`, private)
- `n8n` VM: `n8n-web` (`5678/tcp`, private), `n8n-worker`, `redis`
- `wiki` VM: `wikijs` (`3000`), `edge_reverse_proxy` (`80/443`), bastion SSH

Схема сети:

![Схема сети Ansible VM](./diagrams/network-topolog.png)

## Cloud-сегментация (Terraform)

Явная схема CIDR для текущего стенда:

- private CIDR: `10.10.0.0/28`
- public CIDR: `10.10.0.16/28`

Текущая реализация сети в Terraform:

- `public subnet` - только `wiki` (edge + bastion) с public IP.
- `private subnet` - `db`, `ollama`, `n8n` без public IP.
- Для `private subnet` настроен default route `0.0.0.0/0` через `NAT Gateway` (через route table).

Важно: "шлюз" для private VM в этом контуре - это `NAT Gateway + route table`,
а не вручную заданный IP вида `10.x.x.1` в inventory/ansible.

## Inventory и доступ

Группы inventory:

- `db_hosts`
- `ollama_hosts`
- `n8n_hosts`
- `wiki_hosts`

Модель SSH:

- для `db/ollama/n8n` используется `ansible_ssh_common_args` с `ProxyJump` через `wiki`,
- прямой SSH на внутренние VM извне не нужен,
- `ansible_host` используется для SSH, `private_ip` - для сервисных связей и firewall.

## Роли и playbook, влияющие на сеть

Ключевые роли:

- `firewall`
- `edge_reverse_proxy`
- `edge_tls_acme`
- `postgres_server`
- `ollama_server`
- `n8n_stack`
- `wikijs_server`

Ключевые playbook:

- `site.yml`
- `firewall_reconcile_strict.yml`
- `smoke.yml`

## Разрешенные потоки

### Внешний ingress

| Source                       | Destination | Port/Proto | Назначение                            |
| ---------------------------- | ----------- | ---------- | ------------------------------------- |
| `0.0.0.0/0`                  | `wiki`      | `80/tcp`   | HTTP-01 challenge + redirect на HTTPS |
| `edge_allowed_client_cidrs`  | `wiki`      | `443/tcp`  | доступ к `wiki`/`n8n`                 |
| `firewall_admin_ssh_sources` | `wiki`      | `22/tcp`   | SSH в bastion                         |

### Внутренние потоки между VM

| Source                        | Destination         | Port/Proto            | Назначение                           |
| ----------------------------- | ------------------- | --------------------- | ------------------------------------ |
| `wiki`                        | `n8n`               | `5678/tcp`            | edge proxy -> n8n-web                |
| `n8n`                         | `ollama`            | `11434/tcp`           | n8n -> Ollama API                    |
| `n8n`                         | `db`                | `5432/tcp`            | n8n -> Postgres                      |
| `wiki`                        | `db`                | `5432/tcp`            | Wiki.js -> Postgres                  |
| `wiki`                        | `db`/`ollama`/`n8n` | `22/tcp`              | bastion SSH jump                     |
| `db`/`ollama`/`n8n` (private) | Internet            | `443/tcp`, DNS (`53`) | apt/pull/обновления через NAT egress |

## Что обязано быть закрыто

1. Внешний доступ к `5432` (Postgres).
2. Внешний доступ к `6379` (Redis).
3. Внешний доступ к `5678` (n8n internal).
4. Внешний доступ к `11434` (Ollama).
5. Прямой SSH к `db`/`ollama`/`n8n` извне.

## Firewall политика (роль `firewall`)

### Базовая модель

- backend: `firewalld` на Debian и RedHat,
- zone target: `DROP`,
- правила только source-ограниченные `rich_rule` (IPv4 CIDR),
- broad `--add-port`/`--add-service` не используются,
- на Debian отключается `ufw` (если установлен), чтобы не было конфликта.

### Интерфейсы

- можно задать явно: `firewall_firewalld_interfaces`,
- если список пустой и включен авто-режим,
  используется `ansible_default_ipv4.interface`.

### Verify

Роль проверяет:

- `firewalld --state == running`,
- активную зону и привязку интерфейсов,
- что в зоне нет broad ports/services,
- что effective rich-rules совпадают с декларацией,
- что zone target равен ожидаемому (`DROP`).

### Strict reconcile

`firewall_reconcile_strict.yml` делает:

1. validate входных данных,
2. purge unmanaged entries (ports/services/sources/rich-rules) в зоне,
3. повторный apply декларативных правил,
4. verify effective policy.

Используется как controlled операция очистки drift.

### Docker и firewalld

Роль `firewall` учитывает связку с Docker:

- при изменениях firewalld вызывает handler `Restart docker after firewall changes`
  (только если Docker установлен на хосте),
- дополнительно проверяет наличие chain `DOCKER-FORWARD`,
  и если chain отсутствует - делает self-heal через restart Docker.

Это нужно, чтобы после изменения firewall не ломалось создание Docker bridge-сетей.

## Edge allow-list в nginx

Помимо firewall, в `edge_reverse_proxy` на `location /` и `location = /healthz`
для `wiki` и `n8n` применяется allow-list:

- `allow <CIDR>` из `nginx_rp_allowed_client_cidrs`,
- `allow 127.0.0.1/32`, `allow ::1/128`,
- `deny all`.

Это второй контур ограничения доступа поверх host firewall.

## Smoke-проверки сети

`playbooks/smoke.yml` проверяет:

1. `n8n -> ollama` internal HTTP (`/api/tags`),
2. HTTP-01 challenge path `/.well-known/acme-challenge/*` отдается по HTTP без redirect,
3. edge `HTTP -> HTTPS` redirect для `wiki`/`n8n`,
4. edge HTTPS `/healthz` для `wiki`/`n8n`,
5. блокировку `db -> n8n:5678`,
6. `postgres_hba_rules` с expected `type: host`,
7. срок жизни edge сертификата.

## Операционные команды

```bash
cd deploy/ansible
export ANSIBLE_ROLES_PATH="$(pwd)/roles"
export ANSIBLE_LOCAL_TEMP="$(pwd)/.ansible/tmp"
export ANSIBLE_VAULT_PASSWORD_FILE="${ANSIBLE_VAULT_PASSWORD_FILE:-~/.ansible/vault-pass.txt}"

ansible-playbook -i inventories/cloud/hosts.yml playbooks/bootstrap_python.yml
ansible-playbook -i inventories/cloud/hosts.yml playbooks/site.yml
ansible-playbook -i inventories/cloud/hosts.yml playbooks/smoke.yml
ansible-playbook -i inventories/cloud/hosts.yml playbooks/firewall_reconcile_strict.yml
```
