# n8n_stack

Роль для развертывания стека `n8n` в queue mode через `Docker Compose`: `n8n-web` обслуживает editor/API, `n8n-worker` исполняет queued jobs, `redis` используется как broker очереди.

## Структура роли

```text
.
├── README.md
├── defaults/main.yml
├── handlers/main.yml
├── tasks/
│   ├── main.yml
│   ├── validate.yml
│   ├── setup.yml
│   ├── deploy.yml
│   ├── workflows.yml
│   └── verify.yml
└── templates/
    ├── docker-compose.yml.j2
    ├── n8n.env.j2
    ├── n8n-postgres-credential.json.j2
    └── n8n-postgres-wikijs-credential.json.j2
```

## Что делает

- Проверяет входные переменные (`validate`).
- Создает каталоги стека на хосте (`setup`).
- Рендерит файлы `docker-compose.yml` и `n8n.env`.
- Использует общий `n8n.env` для `n8n-web` и `n8n-worker`.
- Разворачивает стек: `redis` + `n8n-web` + `n8n-worker`.
- Применяет изменения идемпотентно (`deploy`).
- После deploy выполняет явный readiness-check `n8n` по `/healthz`.
- Автоматически bootstrap/import `workflow-as-code` из `n8n/workflows/*.json` после deploy.
- После импорта автоматически публикует workflow, где в JSON задано `"active": true`.
- После публикации автоматически перезапускает `n8n-web`, чтобы production webhooks применились в runtime.
- Автоматически bootstrap'ит credentials `Postgres n8n` и `Postgres wikijs` (без ручного UI) для memory/wiki workflow.
- Импортирует `agent_chat_ui` с `Chat Trigger` для удобного общения прямо в интерфейсе n8n.
- Выполняет проверки после развертывания (`verify`).

Порядок выполнения:
`validate -> setup -> deploy -> flush_handlers -> workflows -> verify`.

## Предусловия

- На хосте уже выполнены роли `common` и `docker_engine`.
- Доступен PostgreSQL.
- Доступен API Ollama.
- Секреты заданы через `ansible-vault`:
  - `n8n_postgres_password`
  - `n8n_common_encryption_key`
  - при необходимости `n8n_redis_password`.

Обычно секреты хранятся как `vault_*` и маппятся на переменные роли
в `host_vars`/`group_vars` (например, `vault_n8n_db_password -> n8n_postgres_password`).

## Граница ответственности

Роль отвечает только за запуск и проверку стека `n8n`.

## Переменные

- `n8n_stack_*` — каталоги, файл `compose`, поведение ожидания.
- `n8n_common_*` — общие настройки `n8n` для `web` и `worker`.
  - включая `n8n_common_agent_system_prompt`, `n8n_common_agent_min_memory_chars`,
    `n8n_common_agent_allow_general_kb` и `n8n_common_agent_debug`
    для удобной настройки поведения ассистента без правок workflow JS.
  - `n8n_common_agent_system_prompt` опционален: если оставить пустым,
    workflow использует встроенный строгий JSON prompt по умолчанию.
  - `n8n_common_agent_memory_schema` и `n8n_common_agent_memory_table`
    задают schema/table для memory workflow (по умолчанию `agent.agent_memory_messages`).
  - `n8n_common_block_env_access_in_node` должен быть `false`,
    если workflow используют `$env` в Code-нодах.
- `n8n_web_*` — параметры `n8n-web`.
- `n8n_worker_*` — параметры `n8n-worker`.
- `n8n_redis_*` — контейнер `redis` и параметры очереди.
- `n8n_postgres_*` — подключение к PostgreSQL.
- `n8n_public_*` — внешний адрес для `N8N_EDITOR_BASE_URL` и `WEBHOOK_URL`.
- `n8n_verify_*` — параметры проверок после развертывания.
- `n8n_workflows_*` — bootstrap/import workflow-файлов в n8n.
  - включая bootstrap PostgreSQL credential для memory workflow.

## Авто-импорт workflow-as-code

Роль поддерживает авто-импорт workflow JSON при деплое:

- файлы берутся с control host из `n8n_workflows_source_dir`,
- копируются на VM в `n8n_workflows_target_dir`,
- монтируются в `n8n-web` контейнер,
- перед импортом workflow автоматически создается PostgreSQL credential (если отсутствует),
- импортируются командой `n8n import:workflow`,
- активные workflow публикуются командой `n8n publish:workflow`,
- после успешного импорта пишется marker `n8n_workflows_state_file`,
  чтобы следующие прогоны не создавали дубли.

По умолчанию:

- импорт включен (`n8n_workflows_bootstrap_enabled: true`),
- выполняется один раз (или принудительно при `n8n_workflows_force_import: true`),
- активность workflow восстанавливается по полю `active` из JSON (`n8n_workflows_activate_after_import: true`).

## Использование

```yaml
- hosts: n8n_hosts
  become: true
  roles:
    - n8n_stack
```

Пример `host_vars/n8n.yml`:

```yaml
n8n_postgres_host: "{{ hostvars['db'].private_ip }}"
n8n_postgres_password: '{{ vault_n8n_db_password }}'
n8n_common_encryption_key: '{{ vault_n8n_encryption_key }}'
n8n_common_ollama_base_url: "http://{{ hostvars['ollama'].private_ip }}:11434"
n8n_common_agent_min_memory_chars: 40
n8n_common_agent_allow_general_kb: false
n8n_common_agent_debug: false
n8n_common_agent_memory_schema: agent
n8n_common_agent_memory_table: agent_memory_messages

n8n_public_host: 'n8n.poluyanov.net'
n8n_public_port: 443
```

## Быстрая проверка

SSH-вариант (опционально): для ручного дебага см. [раздел в основном runbook](../../README.md#manual-ssh).

Команды ниже предполагают, что в текущей shell-сессии уже задан `ANSIBLE_VAULT_PASSWORD_FILE` (см. `deploy/ansible/README.md`, шаг 3).

Проверка уровня роли подтверждает запуск контейнеров, доступность `healthz`
и базовую связность с `Redis`/`PostgreSQL`.

```bash
cd deploy/ansible
ansible -i inventories/cloud/hosts.yml n8n_hosts -b -J -m shell -a "docker ps --filter 'name=n8n-web'"
ansible -i inventories/cloud/hosts.yml n8n_hosts -b -J -m shell -a "docker ps --filter 'name=n8n-worker'"
ansible -i inventories/cloud/hosts.yml n8n_hosts -b -J -m shell -a "docker ps --filter 'name=redis'"
ansible -i inventories/cloud/hosts.yml n8n_hosts -b -J -m shell -a "curl -fsS http://<N8N_PRIVATE_IP>:5678/healthz"
```

Проверка внешнего пользовательского контура (через edge TLS):

```bash
ansible -i inventories/cloud/hosts.yml wiki_hosts -b -J -m shell -a "curl --resolve n8n.poluyanov.net:443:127.0.0.1 --cacert /etc/ssl/certs/ca-certificates.crt https://n8n.poluyanov.net/healthz"
```

Проверка `redis` с паролем:

```bash
ansible -i inventories/cloud/hosts.yml n8n_hosts -b -J -m shell -a "docker exec redis redis-cli -a '<REDIS_PASSWORD>' ping"
```

Проверка `redis` без пароля:

```bash
ansible -i inventories/cloud/hosts.yml n8n_hosts -b -J -m shell -a "docker exec redis redis-cli ping"
```
