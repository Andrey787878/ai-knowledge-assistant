# wikijs_server

Роль разворачивает `Wiki.js` через `Docker Compose` с подключением к внешнему PostgreSQL.

## Что делает

- Проверяет входные переменные (`validate`).
- Создает каталоги проекта и данных на хосте (`setup`).
- Рендерит `docker-compose.yml` и `wikijs.env`.
- Поднимает или обновляет стек `wikijs` (`deploy`).
- Выполняет проверки после развертывания (`verify`).

Порядок выполнения:
`validate -> setup -> deploy -> flush_handlers -> verify`.

## Предусловия

- На хосте уже выполнены роли `base` и `docker_engine`.
- Доступен PostgreSQL (обычно из роли `postgres_server` на VM `db`).
- Секреты заданы через `ansible-vault`:
  - `wikijs_postgres_password`.

Обычно секреты хранятся как `vault_*` и маппятся на переменные роли
в `host_vars`/`group_vars` (например, `vault_wikijs_db_password -> wikijs_postgres_password`).

## Границы роли

Роль отвечает только за запуск и проверку runtime `Wiki.js`.

## Группы переменных

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
wikijs_postgres_password: "{{ vault_wikijs_db_password }}"

wikijs_runtime_bind_host: "{{ private_ip }}"
wikijs_runtime_host_port: 3000
```

## Проверка

Проверка уровня роли подтверждает запуск контейнера, доступность HTTP endpoint
и базовую связность `Wiki.js -> PostgreSQL` по TCP.

```bash
docker ps --filter "name=wikijs"
curl -fsS "http://<WIKI_PRIVATE_IP>:3000/"
docker logs --tail 100 wikijs
```
