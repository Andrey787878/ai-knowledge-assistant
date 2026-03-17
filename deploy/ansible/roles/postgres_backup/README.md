# postgres_backup

Роль для подготовки и эксплуатации backup/restore процесса PostgreSQL.

## Что делает

- Валидирует обязательные переменные роли.
- Создает директории для бэкапов и скриптов.
- Рендерит скрипты `backup-postgres.sh` и `restore-postgres.sh`.
- Опционально настраивает cron-задачу для регулярного backup.
- Использует checksum-файл `SHA256SUMS` для проверки целостности перед restore.
- Проверяет, что контейнер PostgreSQL реально `running` перед backup/restore.
- Поддерживает `current` как symlink на последний backup.

## Предусловия

- Перед `postgres_backup` должны быть выполнены роли `base`, `docker_engine`, `postgres_server`.
- Контейнер PostgreSQL должен быть запущен.
- Файл `postgres.env` должен существовать и содержать `POSTGRES_USER`, `POSTGRES_PASSWORD`.

## Граница ответственности

`postgres_backup` отвечает за backup/restore tooling (скрипты, директории, cron, проверки целостности) и не выполняет restore автоматически в обычном `site.yml`.

## Переменные

Значения по умолчанию задаются в `defaults/main.yml`.

Ключевые переменные:

- `postgres_backup_root_dir` - корневой каталог хранения backup.
- `postgres_backup_current_dir` - symlink на последний backup.
- `postgres_backup_scripts_dir` - каталог скриптов backup/restore.
- `postgres_backup_script_path` - путь скрипта backup.
- `postgres_restore_script_path` - путь скрипта restore.
- `postgres_backup_container_name` - имя контейнера PostgreSQL.
- `postgres_backup_env_file` - путь к `postgres.env`.
- `postgres_backup_databases` - список БД для dump/restore.
- `postgres_backup_include_globals` - включить/выключить dump globals.
- `postgres_backup_prune_enabled` - включить/выключить удаление старых backup.
- `postgres_backup_retention_days` - срок хранения backup в днях.
- `postgres_backup_lock_file` - lock-файл для защиты от параллельных backup/restore запусков.
- `postgres_backup_cron_enabled` - включить/выключить cron backup.
- `postgres_backup_cron_schedule` - cron-расписание backup.
- `postgres_restore_confirm` - защитный флаг ручного restore (`YES`).
- `postgres_restore_source_dir` - путь к backup для restore.
- `postgres_restore_with_globals` - восстанавливать globals или нет.

## Использование

Подготовка backup-инфраструктуры (через роль):

```yaml
- hosts: db_hosts
  become: true
  roles:
    - postgres_backup
```

Запуск backup:

```bash
ansible-playbook -i inventories/cloud/hosts.ini playbooks/backup_postgres.yml
```

Запуск restore (только вручную):

```bash
ansible-playbook -i inventories/cloud/hosts.ini playbooks/restore_postgres.yml \
  -e postgres_restore_confirm=YES \
  -e postgres_restore_source_dir=/var/backups/ai-agent/postgres/20260316-020000
```

Перед restore рекомендуется остановить или перевести в read-only приложения, которые пишут в PostgreSQL (`n8n`, `wikijs`).

Включение очистки старых backup:

```yaml
postgres_backup_prune_enabled: true
postgres_backup_retention_days: 7
```

## Поведение

Роль работает по принципу `fail-fast`: при невалидных переменных завершится ошибкой.

`backup-postgres.sh` создает timestamp-каталог backup, формирует `SHA256SUMS`, обновляет symlink `current`, и при включенном retention удаляет устаревшие backup. Скрипт использует lock-файл для блокировки параллельных backup/restore запусков и при завершении выполняет cleanup временных dump-файлов в контейнере.

`restore-postgres.sh` перед восстановлением проверяет целостность backup через `sha256sum -c`, затем выполняет restore дампов (и globals при включении флага). Скрипт также использует lock-файл для блокировки параллельных backup/restore запусков. При завершении выполняется cleanup временных файлов в контейнере.

Restore не выполняется автоматически в `site.yml` и требует явного подтверждения через `postgres_restore_confirm=YES`.

## Операционные гарантии

- Перед backup/restore скрипты проверяют, что контейнер PostgreSQL запущен.
- Backup и restore используют общий lock-файл, поэтому не выполняются параллельно.
- Перед restore всегда проверяется целостность backup через `SHA256SUMS`.
- При ошибках/прерывании выполняется cleanup временных файлов в контейнере (`/tmp/*.dump`, `/tmp/globals.sql`).

## Типовые причины отказа

- `postgres container is not running` - контейнер PostgreSQL остановлен.
- `POSTGRES_USER/POSTGRES_PASSWORD are required` - в `postgres.env` отсутствуют обязательные переменные.
- `SHA256SUMS not found` или `sha256sum -c` failed - backup неполный или поврежден.
- `another postgres backup/restore process is running` - уже идет другой процесс backup/restore.
- `postgres_restore_confirm` не равен `YES` - защитный флаг restore не подтвержден.

## Быстрая проверка

```bash
ls -la /opt/ai-agent/postgres/scripts
ls -la /var/backups/ai-agent/postgres
readlink -f /var/backups/ai-agent/postgres/current
ansible-playbook -i inventories/cloud/hosts.ini playbooks/backup_postgres.yml
```
