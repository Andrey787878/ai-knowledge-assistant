# deploy/kubernetes/apps/postgres

## Назначение слоя

Этот слой разворачивает `PostgreSQL` для `n8n` и `Wiki.js` и собирает рядом
операционный контур базы: SQL bootstrap, сетевые правила, резервное
копирование и отдельный restore-helmfile для ручного восстановления.

Слой разделяет обычный рабочий деплой и сценарий восстановления. Основной
`helmfile.yaml` отвечает за runtime базы и backup-контур. Отдельный
`helmfile.restore.yaml` используется только по явному запросу, чтобы restore
не был случайной частью обычного `sync`.

## Что применяет Helmfile

Runtime `PostgreSQL` ставится через `../../../vendor_charts/postgresql`, а
служебные ресурсы вокруг него собираются через
`../../../vendor_charts/raw`.

Основной StatefulSet и exporter-конфигурация описаны в `releases/postgres.yaml`.
SQL bootstrap для ролей, баз и служебной схемы лежит в
`releases/initdb-secret.yaml`. Backup-контур собирается через
`releases/backup-cronjob.yaml`. Restore job вынесен в
`releases/restore-job.yaml`. Рабочие и секретные параметры лежат в
`environments/prod/*.values.yaml`.

## Что должно быть готово до применения

До этого слоя уже должен быть применен `deploy/kubernetes/platform`, чтобы в
кластере существовал namespace `db`. На машине, с которой выполняется деплой,
должны быть доступны `sops` и `helm-secrets`, потому что bootstrap и runtime
используют зашифрованные значения.

Этот слой сам по себе не требует наличия `n8n` или `Wiki.js`, но именно он
создает базу и роли, которые потом используют прикладные сервисы.

## Как применять

```bash
cd deploy/kubernetes/apps/postgres

helmfile -e prod build > /tmp/postgres-build.yaml
helmfile -e prod sync
```

Перед фактическим применением полезно именно смотреть итоговый `build`, потому
что здесь в одном state соединяются runtime базы, initdb bootstrap, backup и
policy-ресурсы.

## Как проверять после выкладки

Базовая проверка начинается с StatefulSet, pod-ов, PVC и backup-ресурсов:

```bash
kubectl -n db get sts,pods,svc,pvc,networkpolicy,cronjob
kubectl -n db rollout status sts/postgres-postgresql
```

Если runtime поднялся, но приложения не могут подключиться к базе, смотреть
нужно уже в `pg_hba`, network policy и корректность bootstrap-ролей, а не в
сам факт существования pod-а.

## Как запускать restore

Restore вынесен в отдельный `helmfile.restore.yaml`, чтобы восстановление
требовало явного подтверждения и не смешивалось с обычным деплоем:

```bash
cd deploy/kubernetes/apps/postgres
helmfile -f helmfile.restore.yaml -e prod \
  --state-values-set postgres_restore_enabled=true \
  --state-values-set postgres_restore_job_name=postgres-restore-$(date +%s) \
  --state-values-set postgres_restore_confirm=YES \
  --state-values-set postgres_restore_source=current \
  --state-values-set postgres_restore_with_globals=false \
  sync
```

После завершения восстановления отдельный restore release обычно удаляют:

```bash
helmfile -f helmfile.restore.yaml -e prod destroy
```
