# Карта Ansible: роли и playbook

## Область

Документ описывает карту ролей и playbook Ansible-этапа A, включая зону ответственности и порядок применения.

## Общая архитектура запуска

`playbooks/site.yml` выполняется слоями:

1. `all`: `common` -> `docker_engine` -> `firewall`
2. `db_hosts`: `postgres_server` -> `postgres_backup`
3. `ollama_hosts`: `ollama_server`
4. `n8n_hosts`: `n8n_stack`
5. `wiki_hosts`: `wikijs_server` -> `edge_reverse_proxy` (HTTP bootstrap) -> `edge_tls_acme` -> `edge_reverse_proxy` (финальный HTTPS)

Почему такой порядок:

- сначала baseline и engine на всех хостах,
- потом stateful БД и backup,
- потом сервисы, зависящие от БД/LLM,
- edge TLS в 2 прохода, чтобы сначала отдать HTTP-01 challenge, потом включить строгий HTTPS.

## Плейбуки подробно

### `playbooks/bootstrap_python.yml`

- Где: `all`
- Что делает:
  - `raw` проверяет `python3`,
  - ставит `python3`, если отсутствует.
- Что меняет: только пакет `python3` на целевых VM.
- Когда нужен: первый прогон на “чистых” VM.
- Частая ошибка: неподдерживаемый package manager на хосте.

### `playbooks/site.yml`

- Где: все группы по этапам.
- Что делает: полный деплой инфраструктуры и сервисов.
- Что меняет: пакеты, пользователи, SSH-конфигурацию, политику firewall, compose-стеки, nginx/certbot.
- Повторный запуск: безопасен, должен быть идемпотентен.
- Частая ошибка: не заполнены `hosts.yml` и `zz-local.yml`.

### `playbooks/smoke.yml`

- Где: `localhost`, `n8n_hosts`, `wiki_hosts`, `db_hosts`.
- Что делает:
  - проверяет связность n8n -> ollama/postgres,
  - проверяет edge redirect и HTTPS health,
  - проверяет HTTP-01 challenge path,
  - делает e2e вызов `agent-query`,
  - проверяет, что память сессии записалась в Postgres.
- Что меняет: только временный challenge-файл в webroot (создается и удаляется в рамках smoke).
- Частая ошибка: workflow импортированы, но не активированы/не имеют credentials в n8n.

### Обычное применение `firewall`

- Отдельного `playbooks/firewall.yml` в текущем репо нет.
- Обычное применение firewall выполняется в составе `playbooks/site.yml` (роль `firewall` на `all`).
- Для целевой очистки дрейфа используется `playbooks/firewall_reconcile_strict.yml`.

### `playbooks/firewall_reconcile_strict.yml`

- Где: `all`.
- Что делает:
  - удаляет unmanaged firewalld entries,
  - применяет только декларативные правила из inventory/role vars.
- Когда нужен: контролируемая очистка сетевого дрейфа.
- Важно: запускать осознанно, потому что purge может убрать “ручные” правила.

### `playbooks/backup_postgres.yml`

- Где: `db_hosts`.
- Что делает:
  - запускает backup скрипт,
  - проверяет `current` symlink,
  - проверяет `SHA256SUMS`,
  - проверяет наличие и размер dump-файлов.

### `playbooks/restore_postgres.yml`

- Где: `db_hosts`, `serial: 1`.
- Что делает: restore из конкретного backup-каталога.
- Защиты:
  - обязателен `-e postgres_restore_confirm=YES`,
  - обязателен `-e postgres_restore_source_dir=...`,
  - checksum-проверка перед restore.

## Роли подробно

### `common` (baseline host role)

- Где: `all`.
- Основной поток: `validate -> packages -> filesystem -> automation_user -> ssh_hardening -> timezone -> verify`.
- Что меняет:
  - базовые пакеты (`ca-certificates`, `curl`, `tzdata`, `gnupg*`),
  - `/opt/ai-agent`,
  - automation user и sudoers drop-in,
  - sshd hardening drop-in (`/etc/ssh/sshd_config.d/99-common-hardening.conf`).
- Что проверяет:
  - effective `sshd -T`,
  - `visudo -cf`,
  - owner/mode/content sudoers файла.

### `docker_engine`

- Где: `all` (через `site.yml`).
- Основной поток: `validate -> install_(debian/redhat) -> service -> configure -> verify`.
- Что меняет:
  - репозиторий Docker,
  - пакеты Docker Engine + compose plugin,
  - `/etc/docker/daemon.json` (опционально),
  - сервис `docker`.
- Что проверяет:
  - `docker --version`,
  - `docker compose version`,
  - `systemctl is-enabled/is-active docker`,
  - `docker info` при active-state.

### `firewall`

- Где: `all`.
- Основной поток: `validate -> firewalld apply -> verify`.
- Что меняет:
  - устанавливает и запускает `firewalld`,
  - отключает `ufw` на Debian при наличии,
  - ставит zone target `DROP`,
  - применяет source-based rich rules.
- Что проверяет:
  - firewalld running,
  - активная зона/интерфейсы,
  - отсутствие broad ports/services,
  - соответствие effective rich-rules ожидаемым.
- Docker после изменений firewalld:
  - handler перезапускает Docker (если установлен),
  - self-heal проверяет наличие `DOCKER-FORWARD` и при необходимости чинит через restart Docker.

### `postgres_server`

- Где: `db_hosts`.
- Основной поток: `validate -> install -> deploy -> flush_handlers -> reconcile -> verify`.
- Что меняет:
  - compose/env/pg_hba/init templates в `/opt/ai-agent/postgres`,
  - контейнер postgres,
  - app roles/databases/grants (reconcile),
  - schema/table/indexes памяти агента в БД `n8n`.
- Что проверяет:
  - контейнер running,
  - `pg_isready`,
  - app-level подключения `n8n` и `wikijs`,
  - наличие `agent.agent_memory_messages` и индексов.
- Критичные секреты:
  - `postgres_superuser_password`,
  - `postgres_n8n_password`,
  - `postgres_wiki_password`.

### `postgres_backup`

- Где: `db_hosts`.
- Основной поток: `validate -> setup -> cron`.
- Что меняет:
  - каталоги backup/скриптов,
  - `backup-postgres.sh`, `restore-postgres.sh`,
  - cron job (опционально).
- Особенности:
  - lock-file от параллельных backup/restore,
  - cleanup временных dump в контейнере,
  - checksum `SHA256SUMS`.

### `ollama_server`

- Где: `ollama_hosts`.
- Основной поток: `validate -> setup -> deploy -> flush_handlers -> models -> verify`.
- Что меняет:
  - compose/env в `/opt/ai-agent/ollama`,
  - контейнер Ollama,
  - подтягивает выбранную модель (`ollama pull`).
- Что проверяет:
  - контейнер running,
  - порт `11434`,
  - `/api/tags`,
  - `POST /api/generate` с непустым ответом.

### `n8n_stack`

- Где: `n8n_hosts`.
- Основной поток: `validate -> setup -> deploy -> flush_handlers -> workflows -> verify`.
- Что меняет:
  - compose/env в `/opt/ai-agent/n8n`,
  - контейнеры `redis`, `n8n-web`, `n8n-worker`,
  - импорт workflow JSON из `n8n/workflows`.
- Что проверяет:
  - 3 контейнера running,
  - `n8n /healthz`,
  - TCP связность web -> postgres/redis,
  - `redis-cli ping`.
- Критичные секреты:
  - `n8n_postgres_password`,
  - `n8n_common_encryption_key`,
  - `n8n_common_agent_workflow_token` (если включен token-контур).

### `wikijs_server`

- Где: `wiki_hosts`.
- Основной поток: `validate -> setup -> deploy -> flush_handlers -> verify`.
- Что меняет:
  - compose/env в `/opt/ai-agent/wikijs`,
  - контейнер Wiki.js.
- Что проверяет:
  - контейнер running,
  - HTTP endpoint,
  - TCP доступ до Postgres из контейнера.

### `edge_reverse_proxy`

- Где: `wiki_hosts`.
- Основной поток: `validate -> install -> config -> service -> flush_handlers -> verify`.
- Что меняет:
  - `nginx` package/service,
  - конфиги `n8n.conf` и `wiki.conf`,
  - TLS/security headers,
  - allow-list на уровне `location` в nginx.
- Что проверяет:
  - HTTP/HTTPS listen,
  - `HTTP -> HTTPS` redirect,
  - `/healthz` для `wiki` и `n8n` через HTTPS,
  - наличие security headers.

### `edge_tls_acme`

- Где: `wiki_hosts`.
- Основной поток: `validate -> install -> issue`.
- Что меняет:
  - `certbot`,
  - webroot для HTTP-01,
  - выпуск/обновление LE сертификата,
  - deploy hook `reload nginx`,
  - sync переменных cert/key для edge роли.
- Что проверяет:
  - cert/key существуют после выпуска,
  - `certbot renew --dry-run`.

## Ключевые входные файлы оператора

- `deploy/ansible/inventories/cloud/hosts.yml`:
  реальные адреса и ProxyJump.
- `deploy/ansible/inventories/cloud/group_vars/all/zz-local.yml`:
  локальные CIDR для allow-list.
- `deploy/ansible/inventories/cloud/host_vars/*.yml`:
  host-specific эндпоинты и политики.

Примечание по именам:

- alias `db` в inventory = PostgreSQL VM в инфраструктурной схеме.
- для запуска playbook используйте группу `db_hosts`.

## Базовый операционный сценарий

```bash
cd deploy/ansible
export ANSIBLE_ROLES_PATH="$(pwd)/roles"
export ANSIBLE_LOCAL_TEMP="$(pwd)/.ansible/tmp"
export ANSIBLE_VAULT_PASSWORD_FILE="${ANSIBLE_VAULT_PASSWORD_FILE:-~/.ansible/vault-pass.txt}"

ansible-playbook -i inventories/cloud/hosts.yml playbooks/bootstrap_python.yml
ansible-playbook -i inventories/cloud/hosts.yml playbooks/site.yml
ansible-playbook -i inventories/cloud/hosts.yml playbooks/smoke.yml
```

## Операционные playbook (ручные)

```bash
cd deploy/ansible
ansible-playbook -i inventories/cloud/hosts.yml playbooks/backup_postgres.yml
ansible-playbook -i inventories/cloud/hosts.yml playbooks/restore_postgres.yml -e postgres_restore_confirm=YES -e postgres_restore_source_dir=/var/backups/ai-agent/postgres/<timestamp> -e postgres_restore_with_globals=false
ansible-playbook -i inventories/cloud/hosts.yml playbooks/firewall_reconcile_strict.yml
```

## Быстрый troubleshooting

1. `site.yml` падает на ролях `common/docker/firewall`:
   сначала проверь inventory и `zz-local.yml`.
2. `apt update` на private VM (`db/ollama/n8n`) падает:
   проверь Terraform-сеть (private subnet + NAT gateway + route table `0.0.0.0/0`) и egress в cloud firewall/security groups.
3. `edge_tls_acme` падает:
   проверь DNS и доступность `80/tcp` снаружи.
4. `smoke.yml` падает на e2e:
   проверь, что n8n workflows импортированы и активны, а Postgres credential назначен SQL-нодам.
5. restore не проходит:
   проверь `SHA256SUMS`, корректность каталога backup и что DB writers остановлены/ограничены.
