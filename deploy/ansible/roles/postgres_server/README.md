# postgres_server

Роль для развёртывания PostgreSQL через Docker Compose с TLS и строгими `pg_hba` правилами.

## Что делает

- Валидирует обязательные переменные и секреты.
- Валидирует наличие TLS-файлов, если TLS включен.
- Валидирует структуру каждого правила `postgres_hba_rules` (обязательные поля и допустимые `type`).
- Создает директории проекта PostgreSQL.
- Рендерит:
  - `docker-compose.yml`
  - `postgres.env`
  - `pg_hba.conf`
  - `init.sql`
- Поднимает стек PostgreSQL через `community.docker.docker_compose_v2`.
- Выполняет reconcile-шаг для app roles/databases/grants на каждом прогоне.
- Выполняет verify-проверки:
  - контейнер запущен
  - TCP-порт доступен
  - `pg_isready` возвращает `accepting connections`
  - app-level подключение `n8n` -> `n8n` и `wikijs` -> `wikijs` (`SELECT 1`)

Порядок выполнения в роли:
`validate -> install -> deploy -> flush_handlers -> reconcile -> verify`.

## Предусловия

- Перед `postgres_server` должны быть выполнены роли `base` и `docker_engine`.
- Docker и Docker Compose plugin должны быть доступны на целевом хосте.
- Секреты БД должны быть заданы (рекомендуется через `ansible-vault`).
- При `postgres_tls_enabled: true` на хосте должны существовать TLS-файлы `server.crt` и `server.key` (и `ca.crt`, если включен `postgres_tls_ca_enabled`).

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
- `postgres_tls_enabled`, `postgres_tls_*` - TLS-конфигурация.
- `postgres_tls_manage_file_permissions`, `postgres_tls_*_owner/group/mode` - управление owner/group/mode TLS-файлов на хосте.
- `postgres_compose_wait`, `postgres_compose_wait_timeout` - ожидание старта compose.
- `postgres_reconcile_enabled` - включить/выключить reconcile app roles/databases/grants.
- `postgres_verify_app_connections` - включить/выключить app-level проверки подключений в `verify`.

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
  - type: hostssl
    database: n8n
    user: n8n
    address: "{{ hostvars['n8n'].private_ip }}/32"
    method: scram-sha-256
  - type: hostssl
    database: wikijs
    user: wikijs
    address: "{{ hostvars['wiki'].private_ip }}/32"
    method: scram-sha-256
```

## Поведение

Роль работает по принципу `fail-fast`: при невалидных переменных или отсутствующих TLS-файлах завершается ошибкой.

`init.sql` применяется только при первом init пустого `PGDATA` (поведение Docker Postgres entrypoint): первичный bootstrap.

`reconcile.sql` выполняется после deploy на каждом прогоне (если `postgres_reconcile_enabled: true`) и поддерживает целевое состояние app roles/databases/grants.

Дефолтный `postgres_hba_rules` разрешает только localhost. Доступ `n8n`/`wikijs` задается переопределением в `host_vars/db.yml`.

Изменения `docker-compose.yml`, `postgres.env` и `pg_hba.conf` вызывают handler `Apply postgres stack changes`.

## Быстрая проверка

```bash
docker ps --filter "name=postgres"
docker exec postgres pg_isready -U postgres -d postgres
ss -ltnp | grep 5432
```
