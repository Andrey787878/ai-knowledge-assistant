# wikijs_server

Роль для развертывания `Wiki.js` через `Docker Compose` с подключением к внешнему PostgreSQL.

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
│   └── verify.yml
└── templates/
    ├── docker-compose.yml.j2
    └── wikijs.env.j2
```

## Что делает

- Проверяет входные переменные (`validate`).
- Создает каталоги проекта и данных на хосте (`setup`).
- Рендерит `docker-compose.yml` и `wikijs.env`.
- Поднимает или обновляет стек `wikijs` (`deploy`).
- После deploy ждет HTTP готовность Wiki.js через явный endpoint check.
- Выполняет проверки после развертывания (`verify`).

Порядок выполнения:
`validate -> setup -> deploy -> flush_handlers -> verify`.

## Предусловия

- На хосте уже выполнены роли `common` и `docker_engine`.
- Доступен PostgreSQL (обычно из роли `postgres_server` на VM `db`).
- Секреты заданы через `ansible-vault`:
  - `wikijs_postgres_password`.

Обычно секреты хранятся как `vault_*` и маппятся на переменные роли
в `host_vars`/`group_vars` (например, `vault_wikijs_db_password -> wikijs_postgres_password`).

## Граница ответственности

Роль отвечает только за запуск и проверку runtime `Wiki.js`.

## Переменные

- `wikijs_image_*` - репозиторий, тег, digest, platform.
- `wikijs_runtime_*` - контейнер, порты, healthcheck.
- `wikijs_stack_*` - пути, compose/env, права директорий, поведение deploy.
- `wikijs_stack_data_dir` хранит persistent runtime data на хосте.
- `wikijs_postgres_*` - подключение Wiki.js к PostgreSQL.
- `wikijs_verify_*` - проверки после развертывания.

## Использование

```yaml
- hosts: wiki_hosts
  become: true
  roles:
    - wikijs_server
```

Пример `host_vars/wiki.yml`:

```yaml
wikijs_postgres_host: "{{ hostvars['db'].private_ip }}"
wikijs_postgres_password: '{{ vault_wikijs_db_password }}'

wikijs_runtime_bind_host: '{{ private_ip }}'
wikijs_runtime_host_port: 3000
```

## Быстрая проверка

SSH-вариант (опционально): для ручного дебага см. [раздел в основном runbook](../../README.md#manual-ssh).

Команды ниже предполагают, что в текущей shell-сессии уже задан `ANSIBLE_VAULT_PASSWORD_FILE` (см. `deploy/ansible/README.md`, шаг 3).

Проверка уровня роли подтверждает запуск контейнера, доступность HTTP endpoint
и базовую связность `Wiki.js -> PostgreSQL` по TCP.

```bash
cd deploy/ansible
ansible -i inventories/cloud/hosts.yml wiki_hosts -b -J -m shell -a "docker ps --filter 'name=wikijs'"
ansible -i inventories/cloud/hosts.yml wiki_hosts -b -J -m shell -a "curl -fsS http://127.0.0.1:3000/"
ansible -i inventories/cloud/hosts.yml wiki_hosts -b -J -m shell -a "docker logs --tail 100 wikijs"
```

Проверка внешнего пользовательского контура (через edge TLS):

```bash
ansible -i inventories/cloud/hosts.yml wiki_hosts -b -J -m shell -a "curl --resolve wiki.poluyanov.net:443:127.0.0.1 --cacert /etc/ssl/certs/ca-certificates.crt https://wiki.poluyanov.net/healthz"
```
