# ollama_server

Роль для развертывания и проверки сервиса `Ollama` через `Docker Compose`.

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
│   ├── models.yml
│   └── verify.yml
└── templates/
    ├── docker-compose.yml.j2
    └── ollama.env.j2
```

## Что делает

- Валидирует обязательные переменные роли.
- Создает рабочие директории (`project`, `config`, `data`).
- Рендерит `docker-compose.yml` и `ollama.env`.
- Разворачивает/обновляет стек через `community.docker.docker_compose_v2`.
- Подтягивает одну выбранную модель в Ollama (`ollama_model`).
- Выполняет verify:
  - контейнер запущен;
  - локальный backend-порт доступен;
  - API `GET /api/tags` по локальному HTTP отвечает `200`.
  - `POST /api/generate` возвращает непустой ответ (smoke inference).

## Предусловия

- Перед `ollama_server` должны быть выполнены роли `common`, `docker_engine`.
- Хост должен входить в группу `ollama_hosts`.
- Доступ к Ollama из других VM обеспечивается по private IP и firewall allow-list.

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

SSH-вариант (опционально): для ручного дебага см. [раздел в основном runbook](../../README.md#manual-ssh).

Команды ниже предполагают, что в текущей shell-сессии уже задан `ANSIBLE_VAULT_PASSWORD_FILE` (см. `deploy/ansible/README.md`, шаг 3).

```bash
cd deploy/ansible
ansible -i inventories/cloud/hosts.yml ollama_hosts -b -J -m shell -a "docker ps --filter 'name=ollama'"
ansible -i inventories/cloud/hosts.yml ollama_hosts -b -J -m shell -a "curl -fsS http://<OLLAMA_PRIVATE_IP>:11434/api/tags"
ansible -i inventories/cloud/hosts.yml ollama_hosts -b -J -m shell -a "docker exec ollama ollama list"
```
