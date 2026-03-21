# n8n_stack

Роль разворачивает стек `n8n` в queue mode через `Docker Compose`: `n8n-web` обслуживает editor/API, `n8n-worker` исполняет queued jobs, `redis` используется как broker очереди.

## Что делает

- Проверяет входные переменные (`validate`).
- Создаёт каталоги стека на хосте (`setup`).
- Рендерит файлы `docker-compose.yml` и `n8n.env`.
- Использует общий `n8n.env` для `n8n-web` и `n8n-worker`.
- Разворачивает стек: `redis` + `n8n-web` + `n8n-worker`.
- Применяет изменения идемпотентно (`deploy`).
- Выполняет проверки после развёртывания (`verify`).

Порядок выполнения:
`validate -> setup -> deploy -> flush_handlers -> verify`.

## Предусловия

- На хосте уже выполнены роли `base` и `docker_engine`.
- Доступен PostgreSQL.
- Доступен API Ollama.
- Секреты заданы через `ansible-vault`:
  - `n8n_postgres_password`
  - `n8n_common_encryption_key`
  - при необходимости `n8n_redis_password`.

Обычно секреты хранятся как `vault_*` и маппятся на переменные роли
в `host_vars`/`group_vars` (например, `vault_n8n_db_password -> n8n_postgres_password`).

## Границы роли

Роль отвечает только за запуск и проверку стека `n8n`.

## Группы переменных

- `n8n_stack_*` — каталоги, файл `compose`, поведение ожидания.
- `n8n_common_*` — общие настройки `n8n` для `web` и `worker`.
- `n8n_web_*` — параметры `n8n-web`.
- `n8n_worker_*` — параметры `n8n-worker`.
- `n8n_redis_*` — контейнер `redis` и параметры очереди.
- `n8n_postgres_*` — подключение к PostgreSQL.
- `n8n_public_*` — внешний адрес для `N8N_EDITOR_BASE_URL` и `WEBHOOK_URL`.
- `n8n_verify_*` — параметры проверок после развёртывания.

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

n8n_public_host: 'n8n.example.com'
n8n_public_port: 443
n8n_public_protocol: 'https'
```

## Проверка

Проверка уровня роли подтверждает запуск контейнеров, доступность `healthz`
и базовую связность с `Redis`/`PostgreSQL`.

```bash
docker ps --filter "name=n8n-web"
docker ps --filter "name=n8n-worker"
docker ps --filter "name=redis"
curl -fsS "http://<N8N_PRIVATE_IP>:5678/healthz"
```

Проверка `redis` с паролем:

```bash
docker exec redis redis-cli -a '<REDIS_PASSWORD>' ping
```

Проверка `redis` без пароля:

```bash
docker exec redis redis-cli ping
```
