# PostgreSQL: резервное копирование и восстановление

## Что описывает документ

Документ описывает порядок резервного копирования и восстановления PostgreSQL
в контуре этапа A. Здесь собраны команды ручного запуска, расположение
артефактов и шаги проверки после восстановления.

Используемые компоненты:

- роль `postgres_backup`,
- `deploy/ansible/playbooks/backup_postgres.yml`,
- `deploy/ansible/playbooks/restore_postgres.yml`.

## Предусловия

- PostgreSQL развернут ролью `postgres_server`.
- Роль `postgres_backup` применена на `db_hosts`.
- На DB-хосте доступен `postgres.env` с `POSTGRES_USER` и `POSTGRES_PASSWORD`.
- В текущей shell-сессии задан `ANSIBLE_VAULT_PASSWORD_FILE`
  (см. [deploy/ansible/README.md, шаг 3](../../deploy/ansible/README.md#step-3)).

## Где лежат резервные копии

По умолчанию:

- корень резервных копий: `/var/backups/ai-agent/postgres`,
- symlink на последнюю резервную копию: `/var/backups/ai-agent/postgres/current`,
- скрипты: `/opt/ai-agent/postgres/scripts`.

В timestamp-каталоге:

- `globals.sql` (если включен `postgres_backup_include_globals`),
- `n8n.dump`,
- `wikijs.dump`,
- `SHA256SUMS`.

## Ручной запуск резервного копирования

```bash
cd deploy/ansible
ansible-playbook -i inventories/cloud/hosts.yml playbooks/backup_postgres.yml
```

Playbook:

1. применяет `postgres_backup` (validate/setup),
2. запускает `backup-postgres.sh`,
3. выполняет post-check (`current`, `SHA256SUMS`, число dump-файлов, непустые файлы).

## Включение резервного копирования по расписанию

Пример:

```yaml
postgres_backup_cron_enabled: true
postgres_backup_cron_schedule: '30 2 * * *'
```

Применить через `site.yml` или отдельный playbook.

## Запуск восстановления

Перед восстановлением рекомендуется остановить или изолировать writers
(`n8n`, `wikijs`).

Сначала получи фактический timestamp-каталог из `current`:

```bash
cd deploy/ansible
ansible -i inventories/cloud/hosts.yml db_hosts -b -J -m shell -a \
"readlink -f /var/backups/ai-agent/postgres/current"
```

И используйте путь из вывода (`/var/backups/ai-agent/postgres/<timestamp>`) в восстановлении:

```bash
cd deploy/ansible
ansible-playbook -i inventories/cloud/hosts.yml playbooks/restore_postgres.yml \
  -e postgres_restore_confirm=YES \
  -e postgres_restore_source_dir=/var/backups/ai-agent/postgres/<timestamp> \
  -e postgres_restore_with_globals=false
```

Опционально с `globals.sql`:

```bash
cd deploy/ansible
ansible-playbook -i inventories/cloud/hosts.yml playbooks/restore_postgres.yml \
  -e postgres_restore_confirm=YES \
  -e postgres_restore_source_dir=/var/backups/ai-agent/postgres/20260316-020000 \
  -e postgres_restore_with_globals=true
```

Опционально с авто-остановкой и авто-запуском writers (`managed mode`):

```bash
cd deploy/ansible
ansible-playbook -i inventories/cloud/hosts.yml playbooks/restore_postgres.yml \
  -e postgres_restore_confirm=YES \
  -e postgres_restore_source_dir=/var/backups/ai-agent/postgres/<timestamp> \
  -e postgres_restore_with_globals=false \
  -e postgres_restore_manage_writers=true
```

Защиты восстановления:

- обязательный confirm `postgres_restore_confirm=YES`,
- обязательный `postgres_restore_source_dir`,
- `serial: 1`,
- поддержка symlink источника (`/var/backups/ai-agent/postgres/current`),
- проверка checksum (`sha256sum -c SHA256SUMS`) до восстановления.

В `managed mode` playbook сам:

- останавливает `n8n-web` и `n8n-worker` на хосте `n8n`,
- останавливает `wikijs` на хосте `wiki`,
- выполняет восстановление на `db`,
- поднимает writers обратно в секции `always`.

Практика: для предсказуемости лучше передавать в восстановление явный
timestamp-путь через `readlink -f`, а не `current`.

## Проверка после восстановления

```bash
cd deploy/ansible
ansible -i inventories/cloud/hosts.yml db_hosts -b -J -m shell -a \
"docker exec postgres pg_isready -U postgres -d postgres"
ansible -i inventories/cloud/hosts.yml db_hosts -b -J -m shell -a \
"docker exec postgres psql -U postgres -d n8n -tAc 'SELECT 1'"
ansible -i inventories/cloud/hosts.yml db_hosts -b -J -m shell -a \
"docker exec postgres psql -U postgres -d wikijs -tAc 'SELECT 1'"
```

Дополнительно проверить доступ приложений к БД:

- `n8n -> postgres`,
- `wikijs -> postgres`.

## Частые проблемы

1. `SHA256SUMS not found` - неверный каталог резервной копии.
2. `sha256sum -c failed` - резервная копия повреждена, восстановление нужно остановить.
3. `POSTGRES_USER/POSTGRES_PASSWORD are required` - проблема с `postgres.env`.
4. `dump file count does not match postgres_backup_databases` - рассинхрон списка БД.
