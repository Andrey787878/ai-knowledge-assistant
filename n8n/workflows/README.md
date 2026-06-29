# n8n/workflows

## Что находится в этом каталоге

Этот каталог содержит workflow прикладного контура AI-ассистента. Здесь лежит
не просто набор JSON-файлов для импорта в `n8n`, а фактический контракт
пользовательского сценария: основной запрос к агенту, чтение и запись памяти,
чатовый интерфейс внутри `n8n` и отдельный workflow для прикладной
smoke-проверки.

Файлы из этого каталога импортируются слоем
`deploy/kubernetes/apps/n8n/releases/workflows.yaml` и выступают источником
истины для workflow-контура. Это означает, что изменения workflow должны
рассматриваться как изменения прикладной логики, а не как ручные правки в UI.

## Какие workflow зафиксированы в репозитории

В текущем наборе используются пять workflow:

| Workflow | ID | Trigger | Active | Назначение |
| --- | --- | --- | --- | --- |
| `agent_query_main` | `9c7e0a12-6d2f-4f9c-9ab1-cf2d6c8f5303` | Webhook `agent-query` | `true` | Основная цепочка ответа: входной запрос, извлечение контекста, вызов модели и сбор итогового ответа |
| `memory_read` | `f5d4d6d6-8c5a-4b35-a1e9-0f8e4a6f2101` | Webhook `agent-memory-read` | `true` | Чтение истории сессии из PostgreSQL |
| `memory_write` | `a1b7c2f4-3f20-4f57-9f4e-7f1b8d2f4c02` | Webhook `agent-memory-write` | `true` | Запись сообщения в PostgreSQL |
| `agent_chat_ui` | `7b5e9c1d-4eaa-4a83-bef9-09e1c5d6a901` | Chat Trigger | `true` | Встроенный чат внутри интерфейса `n8n` |
| `agent_smoke_e2e` | `2d9f4b6a-1e44-4a71-8d52-b1c6f7a9d404` | Manual Trigger | `false` | Ручная end-to-end smoke-проверка |

Основной рабочий маршрут пользователя проходит через `agent_query_main`.
Остальные workflow либо обслуживают его внутренние вызовы, либо используются
как отдельные служебные точки входа.

## Как устроена основная цепочка ответа

Прикладная логика строится вокруг одного маршрута:

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

`agent_query_main`, `memory_read` и `memory_write` используют
`responseMode=lastNode`, поэтому HTTP JSON-ответ формируется последней нодой
цепочки и не зависит от отдельной `Respond`-ноды. Это упрощает контракт:
финальный ответ всегда определяется самой прикладной логикой workflow, а не
дополнительным UI-механизмом поверх нее.

## Как устроен webhook-контракт

В production `n8n` хранит webhook-путь в формате
`<workflowId>/<webhook_node_name>/<path>`. Поэтому для стабильного роутинга в
проекте используются отдельные переменные:

- `N8N_AGENT_QUERY_WEBHOOK_PATH`
- `N8N_MEMORY_READ_WEBHOOK_PATH`
- `N8N_MEMORY_WRITE_WEBHOOK_PATH`

Их дефолты для VM-контура заданы в
`deploy/ansible/roles/n8n_stack/defaults/main.yml`.

Здесь есть жесткое ограничение: нельзя переименовывать webhook-ноды или менять
workflow ID без синхронного обновления этих переменных. Если нарушить этот
контракт, внутренние HTTP-вызовы начнут отвечать `404`, хотя workflow могут
оставаться импортированными и активными.

## Какие переменные среды нужны workflow

Для рабочего контура обязательны:

- `INTERNAL_WEBHOOK_BASE_URL`
- `OLLAMA_BASE_URL`
- `N8N_AGENT_QUERY_WEBHOOK_PATH`
- `N8N_MEMORY_READ_WEBHOOK_PATH`
- `N8N_MEMORY_WRITE_WEBHOOK_PATH`
- `N8N_BLOCK_ENV_ACCESS_IN_NODE=false`

Последний пункт обязателен, потому что workflow используют `$env` в
`Code`-нодах. Если доступ к окружению заблокирован, выполнение падает с
ошибкой `access to env vars denied`.

Остальные прикладные параметры задают поведение guard-логики, памяти и поиска
контекста:

| Переменная | Дефолт / требование |
| --- | --- |
| `OLLAMA_MODEL` | `required` |
| `AGENT_WORKFLOW_TOKEN` | `empty` |
| `AGENT_MIN_MEMORY_CHARS` | `40` |
| `AGENT_ALLOW_GENERAL_KB` | `false` |
| `AGENT_DEBUG` | `false` |
| `AGENT_WIKI_MIN_SCORE` | `2` |
| `AGENT_WIKI_MIN_TERM_HITS` | `1` |
| `AGENT_MIN_ANSWER_OVERLAP` | `0` |
| `AGENT_MEMORY_SCHEMA` | `agent` |
| `AGENT_MEMORY_TABLE` | `agent_memory_messages` |
| `AGENT_WIKI_SCHEMA` | `public` |
| `AGENT_WIKI_TABLE` | `pages` |
| `AGENT_WIKI_TITLE_COLUMN` | `title` |
| `AGENT_WIKI_PATH_COLUMN` | `path` |
| `AGENT_WIKI_CONTENT_COLUMN` | `content` |
| `AGENT_WIKI_LIMIT` | `5` |
| `AGENT_WIKI_CONTEXT_CHARS` | `8000` |

В VM-контуре эти значения попадают в `n8n` через
`deploy/ansible/roles/n8n_stack/templates/n8n.env.j2`. В Kubernetes-контуре
они передаются через `ConfigMap` и `Secret` с теми же именами ключей.

## Как работает guard-логика

Workflow рассчитаны не на генерацию ответа любой ценой, а на ответ только в
рамках найденного контекста. Если `AGENT_ALLOW_GENERAL_KB=false`, агент
блокирует мета-вопросы о собственном промпте и внутреннем устройстве, а при
отсутствии достаточного контекста принудительно возвращает `Нет данных.`.

Дополнительно `AGENT_WORKFLOW_TOKEN` позволяет закрыть внутренние webhook
вызовы. В этом режиме `memory_read` и `memory_write` требуют корректный
`token`, а `agent_query_main` прокидывает его во внутренние вызовы. В память
пишутся только те ответы ассистента, которые прошли guard-проверки и отмечены
через `should_persist_assistant=true`.

## Контракт API `agent_query_main`

Основной входной payload выглядит так:

```json
{
  "session_id": "user-123",
  "user_id": "user-123",
  "question": "Как устроена инфраструктура?"
}
```

Допустимо передавать `message` вместо `question`, если вызывающая сторона
использует другой словарь полей.

Успешный ответ выглядит так:

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

Если включен `AGENT_DEBUG=true`, workflow дополнительно возвращает блок `debug`
с промежуточными диагностическими значениями:

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

Этот блок нужен не для обычного клиента, а для ручной диагностики качества
поиска контекста и причин отказа guard-логики.

## Что проверять при типовых ошибках

На практике большая часть проблем укладывается в несколько повторяющихся
сценариев:

| Симптом | Причина | Что проверить |
| --- | --- | --- |
| `404` на webhook | несинхронный webhook path (`ID/node/path`) | `N8N_*_WEBHOOK_PATH`, имена webhook-нод, повторный импорт workflow |
| `code=200 bytes=0` | активная версия workflow не та или есть дрифт | export active workflow, `responseMode`, повторный импорт |
| `500 {"message":"Error in workflow"}` | ошибка в ноде (`$env`, credentials, token, SQL) | execution data, логи `n8n-web` |
| `access to env vars denied` | `N8N_BLOCK_ENV_ACCESS_IN_NODE=true` | выставить `false` и перезапустить `n8n` |
| `invalid token` | включен `AGENT_WORKFLOW_TOKEN`, но token не передан или неверен | payload и фактическое значение `AGENT_WORKFLOW_TOKEN` |
| `credentials not found` или ошибка Postgres-ноды | отсутствует credential `Postgres n8n` или `Postgres wikijs` | bootstrap и reconcile credential-контур |
