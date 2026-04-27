# Этап B (k3s): документация

Единая навигация по Kubernetes-деплою Stage B.

## Быстрые ссылки

- [Главный ранбук Kubernetes-слоя](../../deploy/kubernetes/README.md)
- [Terraform инфраструктура](../../deploy/terraform/k3s_deploy/README.md)
- [Ansible bootstrap](../../deploy/kubernetes/bootstrap/README.md)
- [Platform слой](../../deploy/kubernetes/platform/README.md)
- [Эксплуатация и приемка](./operations-stage-b.md)

## Архитектурные документы

- [Сеть и NetworkPolicy](./network.md)
- [Edge TLS и ACME](./edge-tls-acme.md)
- [Ранбук по сертификатам](./certificates-runbook.md)
- [Backup/Restore PostgreSQL](./backup-restore.md)

## Документация по app-слоям

- [apps/postgres](../../deploy/kubernetes/apps/postgres/README.md)
- [apps/redis](../../deploy/kubernetes/apps/redis/README.md)
- [apps/wiki](../../deploy/kubernetes/apps/wiki/README.md)
- [apps/ollama](../../deploy/kubernetes/apps/ollama/README.md)
- [apps/n8n](../../deploy/kubernetes/apps/n8n/README.md)

## Charts и workflows

- [n8n chart](../../deploy/kubernetes/apps/n8n/chart/README.md)
- [ollama chart](../../deploy/kubernetes/apps/ollama/chart/README.md)
- [n8n workflows](../../n8n/workflows/README.md)

## Рекомендуемый порядок запуска Stage B

1. `deploy/terraform/k3s_deploy`
2. `deploy/kubernetes/bootstrap`
3. `deploy/kubernetes/platform`
4. `deploy/kubernetes/apps/postgres`
5. `deploy/kubernetes/apps/redis`
6. `deploy/kubernetes/apps/wiki`
7. `deploy/kubernetes/apps/ollama`
8. `deploy/kubernetes/apps/n8n`

## Definition Of Done

- Terraform применен без ошибок.
- `bootstrap` smoke прошел, узел `k3s` в `Ready`.
- `cert-manager` и `ClusterIssuer` в `Ready`.
- Все app-слои применяются через `helmfile -e prod sync`.
- Базовые health-проверки `wiki`, `n8n`, `ollama` проходят.
