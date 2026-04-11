# PostgreSQL: резервное копирование и восстановление

## Область

Документ описывает эксплуатационный процесс резервного копирования и восстановления PostgreSQL.

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

## Где лежат backup-артефакты

По умолчанию:

- корень backup: `/var/backups/ai-agent/postgres`,
- symlink на последний backup: `/var/backups/ai-agent/postgres/current`,
- скрипты: `/opt/ai-agent/postgres/scripts`.

В timestamp-каталоге:

- `globals.sql` (если включен `postgres_backup_include_globals`),
- `n8n.dump`,
- `wikijs.dump`,
- `SHA256SUMS`.

## Запуск backup вручную

```bash
cd deploy/ansible
ansible-playbook -i inventories/cloud/hosts.yml playbooks/backup_postgres.yml
```

Playbook:

1. применяет `postgres_backup` (validate/setup),
2. запускает `backup-postgres.sh`,
3. делает post-check (`current`, `SHA256SUMS`, dump count, non-empty files).

## Включение cron backup

Пример:

```yaml
postgres_backup_cron_enabled: true
postgres_backup_cron_schedule: '30 2 * * *'
```

Применить через `site.yml` или отдельный playbook.

## Запуск restore

Перед restore рекомендуется остановить или изолировать writers (`n8n`, `wikijs`).

Сначала получи фактический timestamp-каталог из `current`:

```bash
cd deploy/ansible
ansible -i inventories/cloud/hosts.yml db_hosts -b -J -m shell -a \
"readlink -f /var/backups/ai-agent/postgres/current"
```

И используйте путь из вывода (`/var/backups/ai-agent/postgres/<timestamp>`) в restore:

```bash
cd deploy/ansible
ansible-playbook -i inventories/cloud/hosts.yml playbooks/restore_postgres.yml \
  -e postgres_restore_confirm=YES \
  -e postgres_restore_source_dir=/var/backups/ai-agent/postgres/<timestamp> \
  -e postgres_restore_with_globals=false
```

Опционально с globals:

```bash
cd deploy/ansible
ansible-playbook -i inventories/cloud/hosts.yml playbooks/restore_postgres.yml \
  -e postgres_restore_confirm=YES \
  -e postgres_restore_source_dir=/var/backups/ai-agent/postgres/20260316-020000 \
  -e postgres_restore_with_globals=true
```

Опционально с авто-stop/start writers (managed mode):

```bash
cd deploy/ansible
ansible-playbook -i inventories/cloud/hosts.yml playbooks/restore_postgres.yml \
  -e postgres_restore_confirm=YES \
  -e postgres_restore_source_dir=/var/backups/ai-agent/postgres/<timestamp> \
  -e postgres_restore_with_globals=false \
  -e postgres_restore_manage_writers=true
```

Защиты restore:

- обязательный confirm `postgres_restore_confirm=YES`,
- обязательный `postgres_restore_source_dir`,
- `serial: 1`,
- поддержка symlink источника (`/var/backups/ai-agent/postgres/current`),
- checksum проверка (`sha256sum -c SHA256SUMS`) до восстановления.

Практика: для предсказуемости лучше передавать в restore разрешенный timestamp-путь через `readlink -f`, а не `current`.

## Проверка после restore

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

1. `SHA256SUMS not found` - неверный backup-каталог.
2. `sha256sum -c failed` - поврежденный backup, restore останавливаем.
3. `POSTGRES_USER/POSTGRES_PASSWORD are required` - проблема с `postgres.env`.
4. `dump file count does not match postgres_backup_databases` - рассинхрон списка БД.
