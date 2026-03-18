# ollama_server

Роль для развёртывания и проверки сервиса Ollama через Docker Compose.

## Что делает

- Валидирует обязательные переменные роли.
- Создаёт рабочие директории (`project`, `config`, `data`).
- Рендерит `docker-compose.yml` и `ollama.env`.
- Разворачивает/обновляет стек через `community.docker.docker_compose_v2`.
- Подтягивает одну выбранную модель в Ollama (`ollama_model`).
- Выполняет verify:
  - контейнер запущен;
  - TCP порт доступен;
  - API `GET /api/tags` отвечает `200`.
  - `POST /api/generate` возвращает непустой ответ (smoke inference).

## Предусловия

- Перед `ollama_server` должны быть выполнены роли `base`, `docker_engine`.
- Хост должен входить в группу `ollama_hosts`.
- На хосте должен быть задан `private_ip` (используется в `ollama_bind_host`).

## Граница ответственности

`ollama_server` отвечает за runtime Ollama (deploy/config/verify).

## Переменные

Значения по умолчанию задаются в `defaults/main.yml`.

Ключевые переменные:

- `ollama_image` / `ollama_image_tag` / `ollama_image_digest` - зафиксированный образ.
- `ollama_image_platform` - платформа образа (`linux/amd64`, `linux/arm64/v8`).
- `ollama_bind_host`, `ollama_port` - bind адрес и порт публикации.
- `ollama_project_dir`, `ollama_config_dir`, `ollama_data_dir` - каталоги на хосте.
- `ollama_container_data_dir` - каталог данных внутри контейнера.
- `ollama_compose_wait`, `ollama_compose_wait_timeout` - поведение deploy ожидания.
- `ollama_verify_enabled` - включить/выключить verify-блок роли.
- `ollama_verify_api_url` - URL для API-проверки (`/api/tags`).
- `ollama_keep_alive` - значение `OLLAMA_KEEP_ALIVE` в env.
- `ollama_model` - одна модель, которую нужно держать в Ollama.
- `ollama_verify_generate_enabled` - включить/выключить inference smoke-check.
- `ollama_verify_generate_url` - endpoint для `POST /api/generate`.
- `ollama_verify_generate_prompt` - короткий prompt для проверки генерации.
- `ollama_verify_generate_timeout` - timeout (сек) для inference-check.
- `ollama_healthcheck_*` - параметры healthcheck контейнера.

## Использование

```yaml
- hosts: ollama_hosts
  become: true
  roles:
    - ollama_server
```

## Поведение

Роль работает по принципу `fail-fast`: при невалидных переменных завершится ошибкой.

Роль идемпотентна: повторный запуск не должен вносить изменения без изменения входных переменных или шаблонов.

Если изменяются `docker-compose.yml` или `ollama.env`, вызывается handler `Apply ollama stack changes`.

## Быстрая проверка

```bash
docker ps --filter "name=ollama"
curl -fsS http://<OLLAMA_PRIVATE_IP>:11434/api/tags
docker exec ollama ollama list
```
