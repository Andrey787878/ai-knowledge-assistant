# postgres_server

Роль для развертывания PostgreSQL через Docker Compose со строгими `pg_hba` правилами.

## Структура роли

```text
.
├── README.md
├── defaults/main.yml
├── handlers/main.yml
├── tasks/
│   ├── main.yml
│   ├── validate.yml
│   ├── install.yml
│   ├── deploy.yml
│   ├── reconcile.yml
│   └── verify.yml
└── templates/
    ├── docker-compose.yml.j2
    ├── postgres.env.j2
    ├── pg_hba.conf.j2
    ├── init.sql.j2
    ├── reconcile.sql.j2
    └── agent_memory.sql.j2
```

## Что делает

- Валидирует обязательные переменные и секреты.
- Валидирует структуру каждого правила `postgres_hba_rules` (обязательные поля и допустимые `type`).
- Валидирует `postgres_hba_rules[].address` как корректный IPv4/IPv6 CIDR.
- Создает директории проекта PostgreSQL.
- Рендерит:
  - `docker-compose.yml`
  - `postgres.env`
  - `pg_hba.conf`
  - `init.sql`
- Поднимает стек PostgreSQL через `community.docker.docker_compose_v2`.
- После deploy выполняет явный readiness-check через `pg_isready`.
- Выполняет reconcile-шаг для app roles/databases/grants на каждом прогоне.
- Отмечает `reconcile` как `changed`, когда обнаружен и исправлен drift.
- Создает/поддерживает таблицу памяти агента в БД `n8n`.
- Выполняет verify-проверки:
  - контейнер запущен
  - TCP-порт доступен
  - `pg_isready` возвращает `accepting connections`
  - app-level подключение `n8n` -> `n8n` и `wikijs` -> `wikijs` (`SELECT 1`)
  - наличие таблицы памяти агента и индексов в `n8n` БД

Порядок выполнения в роли:
`validate -> install -> deploy -> flush_handlers -> reconcile -> verify`.

## Предусловия

- Перед `postgres_server` должны быть выполнены роли `common` и `docker_engine`.
- Docker и Docker Compose plugin должны быть доступны на целевом хосте.
- Секреты БД должны быть заданы (рекомендуется через `ansible-vault`).

## Граница ответственности

`postgres_server` отвечает за PostgreSQL runtime (compose, конфиги, bootstrap SQL, deploy, verify).

## Переменные

Значения по умолчанию задаются в `defaults/main.yml`.

Ключевые переменные:

- `postgres_image` - образ Postgres (`tag@digest`).
- `postgres_platform_map`, `postgres_image_platform` - маппинг и вычисленная платформа из `ansible_architecture`.
- `postgres_project_dir`, `postgres_data_dir`, `postgres_config_dir` - пути на хосте.
- `postgres_env_file_path`, `postgres_hba_config_path` - пути конфигов.
- `postgres_bind_host`, `postgres_port`, `postgres_listen_addresses` - сетевые параметры.
- `postgres_superuser`, `postgres_superuser_password`, `postgres_default_db` - bootstrap superuser.
- `postgres_n8n_db`, `postgres_n8n_user`, `postgres_n8n_password` - app-доступ для n8n.
- `postgres_wiki_db`, `postgres_wiki_user`, `postgres_wiki_password` - app-доступ для Wiki.js.
- `postgres_hba_rules` - whitelist правил доступа.
- `postgres_hba_allowed_types` - допустимые значения `type` для правил `pg_hba`.
- `postgres_compose_wait`, `postgres_compose_wait_timeout` - ожидание старта compose.
- `postgres_reconcile_enabled` - включить/выключить reconcile app roles/databases/grants.
- `postgres_verify_app_connections` - включить/выключить app-level проверки подключений в `verify`.
- `postgres_agent_memory_schema`, `postgres_agent_memory_table` - имя schema/table для памяти агента (по умолчанию schema `agent`).
- `postgres_agent_memory_session_created_index`, `postgres_agent_memory_created_at_index` - имена индексов таблицы памяти.

## Использование

```yaml
- hosts: db_hosts
  become: true
  roles:
    - postgres_server
```

Пример для `host_vars/db.yml`:

```yaml
postgres_n8n_password: '{{ vault_postgres_n8n_password }}'
postgres_wiki_password: '{{ vault_postgres_wiki_password }}'
postgres_superuser_password: '{{ vault_postgres_superuser_password }}'

postgres_hba_rules:
  - type: host
    database: all
    user: all
    address: 127.0.0.1/32
    method: scram-sha-256
  - type: host
    database: all
    user: all
    address: ::1/128
    method: scram-sha-256
  - type: host
    database: n8n
    user: n8n
    address: "{{ hostvars['n8n'].private_ip }}/32"
    method: scram-sha-256
  - type: host
    database: wikijs
    user: wikijs
    address: "{{ hostvars['n8n'].private_ip }}/32"
    method: scram-sha-256
  - type: host
    database: wikijs
    user: wikijs
    address: "{{ hostvars['wiki'].private_ip }}/32"
    method: scram-sha-256
```

## Поведение

Роль работает по принципу `fail-fast`: при невалидных переменных завершается ошибкой.

`init.sql` применяется только при первом init пустого `PGDATA` (поведение Docker Postgres entrypoint): первичный bootstrap.

`reconcile.sql` выполняется после deploy на каждом прогоне (если `postgres_reconcile_enabled: true`) и поддерживает целевое состояние app roles/databases/grants.
Перед `reconcile` выполняется drift-check, поэтому шаг помечается `changed` только при реальном выравнивании состояния.

Reconcile также поддерживает отдельную schema `agent`, таблицу памяти агента (`session_id`, `role`, `message`, `metadata`, `created_at`) и нужные индексы в БД `n8n`.
Для роли `n8n` дополнительно поддерживаются `GRANT USAGE` на schema памяти и `search_path = agent,public` в БД `n8n`.

`postgres_server` работает по private-network модели: доступ `n8n`/`wikijs` задается явными CIDR в `postgres_hba_rules` через `host_vars/db.yml`.
Значения `address` в `postgres_hba_rules` должны быть валидным CIDR (например, `10.10.0.12/32` или `2001:db8::1/128`).
Рекомендуется использовать точечные правила для нужных пар `database/user/source` и не оставлять fallback `all/all` для внешних IP.

Изменения `docker-compose.yml`, `postgres.env` и `pg_hba.conf` вызывают handler `Apply postgres stack changes`.
Verify-задачи выполняются в обычном режиме запуска и пропускаются в `--check`.

## Быстрая проверка

SSH-вариант (опционально): для ручного дебага см. [раздел в основном runbook](../../README.md#manual-ssh).

Команды ниже предполагают, что в текущей shell-сессии уже задан `ANSIBLE_VAULT_PASSWORD_FILE` (см. `deploy/ansible/README.md`, шаг 3).

```bash
cd deploy/ansible
ansible -i inventories/cloud/hosts.yml db_hosts -b -J -m shell -a "docker ps --filter 'name=postgres'"
ansible -i inventories/cloud/hosts.yml db_hosts -b -J -m shell -a "docker exec postgres pg_isready -U postgres -d postgres"
ansible -i inventories/cloud/hosts.yml db_hosts -b -J -m shell -a "ss -ltnp | grep 5432"
```
