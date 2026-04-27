# deploy/kubernetes/apps/postgres

## Что это
Слой PostgreSQL для `n8n` и `wikijs`: runtime БД, initdb, backup и опциональный restore.

## Что ставится

- PostgreSQL StatefulSet
- initdb Secret (создание ролей/БД и служебной схемы)
- NetworkPolicy
- backup CronJob + backup PVC
- restore Job (отдельным restore-helmfile, по запросу)

## Какие chart используются

- `../../../vendor_charts/postgresql` (upstream `bitnami/postgresql`) для runtime
- `../../../vendor_charts/raw` (upstream `bedag/raw`) для ops-ресурсов

## Основные файлы

- `helmfile.yaml` — основной деплой
- `helmfile.restore.yaml` — ручной restore
- `releases/postgres.yaml` — runtime postgres
- `releases/initdb-secret.yaml` — SQL bootstrap
- `releases/backup-cronjob.yaml` — backup
- `releases/restore-job.yaml` — restore job
- `environments/prod/*.values.yaml` — конфиг
- `environments/prod/secrets.values.enc.yaml` — SOPS-секреты

## Зависимости

- `deploy/kubernetes/platform` уже применен (namespace `db` существует)
- настроены `sops` и `helm-secrets`

## Как применять

```bash
cd deploy/kubernetes/apps/postgres

# Проверка рендера
helmfile -e prod build > /tmp/postgres-build.yaml

# Применение
helmfile -e prod sync
```

## Проверка

```bash
kubectl -n db get sts,pods,svc,pvc,networkpolicy,cronjob
kubectl -n db rollout status sts/postgres-postgresql
```

## Restore (коротко)

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

После завершения restore release обычно удаляют:

```bash
helmfile -f helmfile.restore.yaml -e prod destroy
```
