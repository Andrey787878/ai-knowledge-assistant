# Этапы B и C: single-node k3s, Helmfile, CI/CD и наблюдаемость

Этот раздел собирает документацию по Kubernetes-контуру проекта. Здесь
описаны подготовка инфраструктуры, bootstrap `k3s`, структура Helmfile-слоев,
сеть, наблюдаемость и путь доставки изменений.

## Что описывает этот раздел

Этап B разворачивает single-node `k3s` и прикладные сервисы в Kubernetes через
`Helmfile`:

- `platform` (namespaces + cert-manager + ClusterIssuer)
- `observability` (Prometheus + Alertmanager + Grafana + Loki + Alloy)
- `db` (PostgreSQL + задания резервного копирования и восстановления)
- `n8n` (n8n-web + n8n-worker + redis + задания с workflow)
- `wiki` (Wiki.js)
- `ollama` (Ollama + задание загрузки модели)

Этап C добавляет поверх контура этапа B три эксплуатационных слоя:

- CI для валидации инфраструктурного кода;
- CD для выкладки через Helmfile;
- наблюдаемость для контроля состояния системы.

## Основные документы

### Запуск и приемка

- [Terraform: инфраструктура этапа B](../../deploy/terraform/k3s_deploy/README.md)
- [Ansible bootstrap k3s](../../deploy/kubernetes/bootstrap/README.md)
- [Руководство по Kubernetes-деплою](../../deploy/kubernetes/README.md)
- [CI/CD для этапов B и C](./ci-cd.md)
- [Эксплуатация и приемка](./operations.md)
- [Карта Helmfile и release-файлов](./helmfiles-releases-map.md)

### CI/CD

- [Отдельное руководство по CI/CD](./ci-cd.md)
- `CI`: `.github/workflows/ci.yml`
- `CD auto`: `.github/workflows/cd-k3s-auto.yml`
- `CD manual`: `.github/workflows/cd-k3s-manual.yml`

CD работает через отдельную виртуальную машину `runner`, которая создается в
`deploy/terraform/k3s_deploy`, попадает в inventory group
`private_hosts -> github_runners`, подготавливается ролью `github_runner` и
регистрируется как self-hosted GitHub Actions runner с labels
`self-hosted, linux, x64, k3s, prod, deploy, stage-b`.

Виртуальная машина `runner` остается внутренней private-only VM: снаружи доступен только
публичный `k3s`, а доступ к `runner` идет через `ProxyJump` и private
endpoint Kubernetes API.

`cd-k3s-auto.yml` запускается только после успешного `CI` для коммита,
который уже попал в `main`, и выкатывает только измененные слои Helmfile.
`cd-k3s-manual.yml` поддерживает три режима:
`full`, `scope`, `changed`. После выкладки workflow выполняет smoke-проверки
по областям для `platform`, `observability`, `postgres`, `redis`, `wiki`,
`ollama` и `n8n`.

Ручной деплой тоже не обходит проверку качества: перед выкладкой workflow
проверяет, что для выбранного `ref` существует успешный запуск `CI`.

Режим `changed` здесь считается вспомогательным: он вычисляет область из
`git diff` относительно выбранного `ref` и полезен для повторного частичного
выката, когда различия хорошо понятны. Для самого предсказуемого сценария в
production предпочтительнее `full` или явный `scope`.

### Сеть и безопасность

- [Сеть и NetworkPolicy](./network.md)
- [Ingress TLS и ACME](./ingress-tls-acme.md)
- [Ранбук по сертификатам](./certificates-runbook.md)

### Наблюдаемость, SLI и SLO

- [SLI и SLO](./sli-slo.md)
- [Мониторинг, алертинг и дашборды](./monitoring.md)

### Данные

- [PostgreSQL: резервное копирование и восстановление](./backup-restore.md)

### Слои и приложения

- [Слой platform](../../deploy/kubernetes/platform/README.md)
- [Слой observability](../../deploy/kubernetes/observability/README.md)
- [apps/postgres](../../deploy/kubernetes/apps/postgres/README.md)
- [apps/redis](../../deploy/kubernetes/apps/redis/README.md)
- [apps/wiki](../../deploy/kubernetes/apps/wiki/README.md)
- [apps/ollama](../../deploy/kubernetes/apps/ollama/README.md)
- [apps/n8n](../../deploy/kubernetes/apps/n8n/README.md)

### Проектные Helm-чарты

Ниже перечислены Helm-чарты, которые разрабатываются в проекте
(`deploy/kubernetes/apps/*/chart`), в отличие от вендорных снапшотов в
`deploy/kubernetes/vendor_charts`.

- [n8n chart](../../deploy/kubernetes/apps/n8n/chart/README.md)
- [ollama chart](../../deploy/kubernetes/apps/ollama/chart/README.md)
