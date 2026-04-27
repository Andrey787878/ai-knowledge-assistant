# PostgreSQL: backup и restore (Этап B)

Короткий ранбук по резервному копированию и восстановлению PostgreSQL в Kubernetes.

## Оглавление

- [Что используется](#step-1)
- [Проверка перед работой](#step-2)
- [Запуск backup](#step-3)
- [Запуск restore](#step-4)
- [Проверка после restore](#step-5)
- [Частые ошибки](#step-6)

<a id="step-1"></a>

## Что используется

- `deploy/kubernetes/apps/postgres/releases/backup-cronjob.yaml`
- `deploy/kubernetes/apps/postgres/releases/restore-job.yaml`
- `deploy/kubernetes/apps/postgres/scripts/backup-postgres.sh`
- `deploy/kubernetes/apps/postgres/scripts/restore-postgres.sh`

Backup хранится в PVC `postgres-backups` через CronJob `postgres-backup`.

<a id="step-2"></a>

## Проверка перед работой

```bash
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config-k3s}"
kubectl -n db get pods,svc,pvc,cronjob
kubectl -n db rollout status sts/postgres-postgresql
```

Если `apps/postgres` еще не применен:

```bash
cd deploy/kubernetes/apps/postgres
helmfile -e prod sync
```

<a id="step-3"></a>

## Запуск backup

Ручной запуск из CronJob:

```bash
JOB="postgres-backup-manual-$(date +%s)"
kubectl -n db create job --from=cronjob/postgres-backup "$JOB"
kubectl -n db wait --for=condition=complete --timeout=600s "job/$JOB"
kubectl -n db logs "job/$JOB" --tail=200
kubectl -n db get jobs --sort-by=.metadata.creationTimestamp
```

Проверка целостности backup на PVC (`SHA256SUMS` + чтение dump):

```bash
kubectl -n db run backup-inspect --restart=Never --image=postgres:18.3-bookworm \
  --overrides='{"spec":{"containers":[{"name":"backup-inspect","image":"postgres:18.3-bookworm","command":["sh","-lc","set -e; ls -lah /backups/current; sha256sum -c /backups/current/SHA256SUMS; pg_restore -l /backups/current/n8n.dump >/dev/null; pg_restore -l /backups/current/wikijs.dump >/dev/null; echo OK"],"volumeMounts":[{"name":"backups","mountPath":"/backups"}]}],"volumes":[{"name":"backups","persistentVolumeClaim":{"claimName":"postgres-backups"}}]}}'
kubectl -n db wait --for=condition=Ready --timeout=180s pod/backup-inspect
kubectl -n db logs backup-inspect --tail=200
kubectl -n db delete pod backup-inspect --wait=true
```

Локальная обертка:

```bash
cd deploy/kubernetes/apps/postgres
bash scripts/backup-postgres.sh
```

Изменить расписание/retention:

- правим `environments/prod/backup.values.yaml`
- применяем `helmfile -e prod sync`

<a id="step-4"></a>

## Запуск restore

One-shot restore через `helmfile.restore.yaml`:

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

После завершения выключить restore release:

```bash
cd deploy/kubernetes/apps/postgres
helmfile -f helmfile.restore.yaml -e prod destroy
```

Локальная обертка:

```bash
cd deploy/kubernetes/apps/postgres
RESTORE_CONFIRM=YES bash scripts/restore-postgres.sh /var/backups/ai-agent/postgres/current false
```

Примечание: `scripts/restore-postgres.sh` читает backup из локального пути на машине оператора.

<a id="step-5"></a>

## Проверка после restore

```bash
kubectl -n db exec postgres-postgresql-0 -- sh -lc '
PW="$(cat /opt/bitnami/postgresql/secrets/postgres-password 2>/dev/null || cat /opt/bitnami/postgresql/secrets/password 2>/dev/null)"
PGPASSWORD="$PW" psql -U postgres -d postgres -tAc "SELECT 1"
PGPASSWORD="$PW" psql -U postgres -d n8n -tAc "SELECT 1"
PGPASSWORD="$PW" psql -U postgres -d wikijs -tAc "SELECT 1"
'
```

Проверить приложения:

- `wiki` читает/пишет в `wikijs` БД
- `n8n` выполняет workflow без ошибок БД

<a id="step-6"></a>

## Частые ошибки

`restore blocked by confirm`:

- не задан `postgres_restore_confirm=YES`

`backup source not found`:

- неверный `postgres_restore_source`

`app cannot connect after restore`:

- рассинхрон паролей в Kubernetes Secret и app values

`initdb changes not visible`:

- `initdb` применяется только на пустом data volume

## Источники

- [apps/postgres README](../../deploy/kubernetes/apps/postgres/README.md)
- [backup-cronjob release](../../deploy/kubernetes/apps/postgres/releases/backup-cronjob.yaml)
- [restore-job release](../../deploy/kubernetes/apps/postgres/releases/restore-job.yaml)
