# Этапы B и C (single-node k3s): документация Terraform + Ansible bootstrap + Helmfile + CI/CD + observability

Единая точка входа в документацию этапов B и C.

## Назначение

Этап B разворачивает single-node k3s и сервисы в Kubernetes через Helmfile:

- `platform` (namespaces + cert-manager + ClusterIssuer)
- `observability` (Prometheus + Alertmanager + Grafana + Loki + Alloy)
- `db` (PostgreSQL + backup/restore jobs)
- `n8n` (n8n-web + n8n-worker + redis + workflows jobs)
- `wiki` (Wiki.js)
- `ollama` (Ollama + model-pull job)

Этап C добавляет к этому контуру три операционных слоя:

- CI для валидации инфраструктурного кода;
- CD для деплоя через helmfile;
- observability для наблюдаемости системы.

## Запуск и приемка

- [Terraform: инфраструктура этапа B](../../deploy/terraform/k3s_deploy/README.md)
- [Ansible bootstrap k3s](../../deploy/kubernetes/bootstrap/README.md)
- [Ранбук Kubernetes-деплоя](../../deploy/kubernetes/README.md)
- [CI/CD для этапов B+C](./ci-cd.md)
- [Эксплуатация и приемка](./operations.md)
- [Карта helmfile/release](./helmfiles-releases-map.md)

## CI/CD

- [Отдельный CI/CD runbook](./ci-cd.md)
- `CI`: `.github/workflows/ci.yml`
- `CD auto`: `.github/workflows/cd-k3s-auto.yml`
- `CD manual`: `.github/workflows/cd-k3s-manual.yml`

CD работает через отдельную VM `runner`, которая создается в
`deploy/terraform/k3s_deploy`, попадает в inventory group `github_runners`,
bootstrap-ится ролью `github_runner` и регистрируется как self-hosted GitHub
Actions runner с labels `self-hosted, linux, x64, k3s, prod, deploy, stage-b`.

`cd-k3s-auto.yml` запускается только после успешного `CI` для коммита,
который уже попал в `main`, и выкатывает только измененные Helmfile-слои.
`cd-k3s-manual.yml` поддерживает три режима:
`full`, `scope`, `changed`. После deploy workflow выполняет scope-aware smoke
checks для `platform`, `observability`, `postgres`, `redis`, `wiki`, `ollama`
и `n8n`.

Ручной deploy тоже не обходит quality gate: перед выкладкой workflow проверяет,
что для выбранного `ref` существует успешный `CI` run.

Режим `changed` здесь считается best-effort режимом: он вычисляет scope из
git diff относительно выбранного `ref` и полезен для повторного частичного
выката, когда diff хорошо понятен. Для самого детерминированного production
path предпочтительнее `full` или явный `scope`.

## Сеть и безопасность

- [Сеть и NetworkPolicy](./network.md)
- [Ingress TLS и ACME](./ingress-tls-acme.md)
- [Ранбук по сертификатам](./certificates-runbook.md)

## Observability и SLA

- [SLI и SLO](./sli-slo.md)
- [Monitoring, alerting и dashboards](./monitoring.md)

## Данные

- [PostgreSQL: backup/restore](./backup-restore.md)

## Слои и приложения

- [Platform слой](../../deploy/kubernetes/platform/README.md)
- [Observability слой](../../deploy/kubernetes/observability/README.md)
- [apps/postgres](../../deploy/kubernetes/apps/postgres/README.md)
- [apps/redis](../../deploy/kubernetes/apps/redis/README.md)
- [apps/wiki](../../deploy/kubernetes/apps/wiki/README.md)
- [apps/ollama](../../deploy/kubernetes/apps/ollama/README.md)
- [apps/n8n](../../deploy/kubernetes/apps/n8n/README.md)

## Проектные Helm charts (apps)

Ниже перечислены Helm charts, которые разрабатываются в проекте (`deploy/kubernetes/apps/*/chart`), в отличие от вендорных снапшотов в `deploy/kubernetes/vendor_charts`.

- [n8n chart](../../deploy/kubernetes/apps/n8n/chart/README.md)
- [ollama chart](../../deploy/kubernetes/apps/ollama/chart/README.md)
