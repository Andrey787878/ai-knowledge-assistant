# n8n workflows

Набор workflow AI-ассистента:

- `agent_query_main.json`
- `memory_read.json`
- `memory_write.json`
- `agent_chat_ui.json`
- `agent_smoke_e2e.json`

## Каталог workflow

| Workflow           | ID                                     | Trigger                      | Active  | Назначение                                                       |
| ------------------ | -------------------------------------- | ---------------------------- | ------- | ---------------------------------------------------------------- |
| `agent_query_main` | `9c7e0a12-6d2f-4f9c-9ab1-cf2d6c8f5303` | Webhook `agent-query`        | `true`  | Главная API-цепочка: input -> wiki context -> Ollama -> response |
| `memory_read`      | `f5d4d6d6-8c5a-4b35-a1e9-0f8e4a6f2101` | Webhook `agent-memory-read`  | `true`  | Чтение истории сессии из PostgreSQL                              |
| `memory_write`     | `a1b7c2f4-3f20-4f57-9f4e-7f1b8d2f4c02` | Webhook `agent-memory-write` | `true`  | Запись сообщения в PostgreSQL                                    |
| `agent_chat_ui`    | `7b5e9c1d-4eaa-4a83-bef9-09e1c5d6a901` | Chat Trigger                 | `true`  | Встроенный UI чат внутри n8n                                     |
| `agent_smoke_e2e`  | `2d9f4b6a-1e44-4a71-8d52-b1c6f7a9d404` | Manual Trigger               | `false` | Ручной e2e smoke workflow                                        |

## Логика цепочки

```text
Client / Chat UI
   -> agent_query_main
      -> memory_write (user)
      -> wiki_read (Postgres wikijs/pages)
      -> Ollama /api/generate
      -> guard/normalization
      -> memory_write (assistant, only if should_persist_assistant=true)
      -> API response
```

`agent_query_main`, `memory_read` и `memory_write` используют `responseMode=lastNode`, поэтому HTTP JSON-ответ формируется последней нодой цепочки и не зависит от отдельной `Respond`-ноды.

## Webhook path контракт

В n8n production webhook путь хранится с префиксом
`<workflowId>/<webhook_node_name>/<path>`.

Поэтому в этом проекте роутинг задается через env:

- `N8N_AGENT_QUERY_WEBHOOK_PATH`
- `N8N_MEMORY_READ_WEBHOOK_PATH`
- `N8N_MEMORY_WRITE_WEBHOOK_PATH`

Дефолты для Ansible заданы в:
`deploy/ansible/roles/n8n_stack/defaults/main.yml`.

Важно:

- не переименовывать webhook-ноды и не менять workflow ID без синхронного обновления этих env,
- иначе внутренние HTTP-вызовы начнут давать `404`.

## Env-контракт

### Обязательные для рабочего контура

- `INTERNAL_WEBHOOK_BASE_URL`
- `OLLAMA_BASE_URL`
- `N8N_AGENT_QUERY_WEBHOOK_PATH`
- `N8N_MEMORY_READ_WEBHOOK_PATH`
- `N8N_MEMORY_WRITE_WEBHOOK_PATH`
- `N8N_BLOCK_ENV_ACCESS_IN_NODE=false`

Почему последний пункт обязателен: workflow используют `$env` в Code-нодах.
Если доступ к env заблокирован: `Error: access to env vars denied`.

### Параметры (дефолты/требования)

| Переменная                  | Дефолт / требование     |
| --------------------------- | ----------------------- |
| `OLLAMA_MODEL`              | `required`              |
| `AGENT_WORKFLOW_TOKEN`      | `empty`                 |
| `AGENT_MIN_MEMORY_CHARS`    | `40`                    |
| `AGENT_ALLOW_GENERAL_KB`    | `false`                 |
| `AGENT_DEBUG`               | `false`                 |
| `AGENT_WIKI_MIN_SCORE`      | `2`                     |
| `AGENT_WIKI_MIN_TERM_HITS`  | `1`                     |
| `AGENT_MIN_ANSWER_OVERLAP`  | `0`                     |
| `AGENT_MEMORY_SCHEMA`       | `agent`                 |
| `AGENT_MEMORY_TABLE`        | `agent_memory_messages` |
| `AGENT_WIKI_SCHEMA`         | `public`                |
| `AGENT_WIKI_TABLE`          | `pages`                 |
| `AGENT_WIKI_TITLE_COLUMN`   | `title`                 |
| `AGENT_WIKI_PATH_COLUMN`    | `path`                  |
| `AGENT_WIKI_CONTENT_COLUMN` | `content`               |
| `AGENT_WIKI_LIMIT`          | `5`                     |
| `AGENT_WIKI_CONTEXT_CHARS`  | `8000`                  |

### Где задаются переменные

- Ansible/VM: `deploy/ansible/roles/n8n_stack/templates/n8n.env.j2`
- Kubernetes: ConfigMap/Secret с теми же именами ключей

## Безопасность и guard-логика

- Рекомендуется задавать `AGENT_WORKFLOW_TOKEN` непустым:
  - `memory_read` и `memory_write` тогда требуют валидный `token`,
  - `agent_query_main` прокидывает token во внутренние вызовы.
- При `AGENT_ALLOW_GENERAL_KB=false`:
  - блокируются meta-вопросы о промпте/внутренностях,
  - при отсутствии контекста ответ принудительно `Нет данных.`,
  - в память пишутся только "чистые" ответы (`should_persist_assistant=true`).

## Контракт API `agent_query_main`

Вход:

```json
{
	"session_id": "user-123",
	"user_id": "user-123",
	"question": "Как устроена инфраструктура?"
}
```

Допустимо `message` вместо `question`.

Успешный выход:

```json
{
	"ok": true,
	"trace_id": "user-123-1712600000000",
	"session_id": "user-123",
	"user_id": "user-123",
	"question": "Как устроена инфраструктура?",
	"answer": "...",
	"citations": ["D1"]
}
```

При `AGENT_DEBUG=true` добавляется `debug`:

```json
{
	"memory_count": 4,
	"memory_has_context": true,
	"top_score": 12.3,
	"top_term_hits": 3,
	"question_terms_count": 4,
	"min_wiki_score": 2,
	"min_term_hits": 1,
	"is_identity_question": false,
	"is_meta_question": false,
	"guard_reason": "ok",
	"overlap_count": 6,
	"prompt_preview": "..."
}
```

## Типовые ошибки

| Симптом                                      | Причина                                                      | Что проверить                                                  |
| -------------------------------------------- | ------------------------------------------------------------ | -------------------------------------------------------------- |
| `404` на webhook                             | несинхронный webhook path (`ID/node/path`)                   | `N8N_*_WEBHOOK_PATH`, имена webhook-нод, реимпорт workflow     |
| `code=200 bytes=0`                           | активная версия workflow не та/дрифт                         | экспорт active workflow, `responseMode`, принудительный импорт |
| `500 {"message":"Error in workflow"}`        | ошибка в ноде (`$env`, credentials, token, SQL)              | `execution_entity + execution_data`, `docker logs n8n-web`     |
| `access to env vars denied`                  | `N8N_BLOCK_ENV_ACCESS_IN_NODE=true`                          | выставить `false` и перезапустить n8n                          |
| `invalid token`                              | включен `AGENT_WORKFLOW_TOKEN`, но token не передан/неверный | проверить payload и `AGENT_WORKFLOW_TOKEN`                     |
| `credentials not found`/ошибка Postgres-ноды | отсутствует credential `Postgres n8n` или `Postgres wikijs`  | bootstrap/reconcile credential через Ansible                   |
