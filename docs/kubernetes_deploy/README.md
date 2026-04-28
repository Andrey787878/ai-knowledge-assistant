# Этап B (single-node k3s): документация Terraform + Ansible bootstrap + Helmfile

Единая точка входа в документацию этапа B.

## Назначение

Этап B разворачивает single-node k3s и сервисы в Kubernetes через Helmfile:

- `platform` (namespaces + cert-manager + ClusterIssuer)
- `db` (PostgreSQL + backup/restore jobs)
- `n8n` (n8n-web + n8n-worker + redis + workflows jobs)
- `wiki` (Wiki.js)
- `ollama` (Ollama + model-pull job)

## Запуск и приемка

- [Terraform: инфраструктура этапа B](../../deploy/terraform/k3s_deploy/README.md)
- [Ansible bootstrap k3s](../../deploy/kubernetes/bootstrap/README.md)
- [Ранбук Kubernetes-деплоя](../../deploy/kubernetes/README.md)
- [Эксплуатация и приемка](./operations.md)
- [Карта helmfile/release](./helmfiles-releases-map.md)

## Сеть и безопасность

![Схема сети этапа B](./diagrams/network-topology.png)

- [Сеть и NetworkPolicy](./network.md)
- [Ingress TLS и ACME](./ingress-tls-acme.md)
- [Ранбук по сертификатам](./certificates-runbook.md)

## Данные

- [PostgreSQL: backup/restore](./backup-restore.md)

## Слои и приложения

- [Platform слой](../../deploy/kubernetes/platform/README.md)
- [apps/postgres](../../deploy/kubernetes/apps/postgres/README.md)
- [apps/redis](../../deploy/kubernetes/apps/redis/README.md)
- [apps/wiki](../../deploy/kubernetes/apps/wiki/README.md)
- [apps/ollama](../../deploy/kubernetes/apps/ollama/README.md)
- [apps/n8n](../../deploy/kubernetes/apps/n8n/README.md)

## Проектные Helm charts (apps)

Ниже перечислены Helm charts, которые разрабатываются в проекте (`deploy/kubernetes/apps/*/chart`), в отличие от вендорных снапшотов в `deploy/kubernetes/vendor_charts`.

- [n8n chart](../../deploy/kubernetes/apps/n8n/chart/README.md)
- [ollama chart](../../deploy/kubernetes/apps/ollama/chart/README.md)
