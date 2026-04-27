# Этап B (k3s): деплой через Terraform + Ansible + Kubernetes + Helm

Единая точка входа в документацию этапа B, где:

- Terraform отвечает за инфраструктуру single-node k3s,
- Ansible bootstrap отвечает за подготовку VM и установку k3s,
- Kubernetes + Helmfile отвечают за platform и application слои.

## Архитектура и сеть этапа B

![Архитектура и сеть этапа B](./diagrams/network-topology.png)

## Запуск и приемка

- [Terraform: инфраструктура k3s](../../deploy/terraform/k3s_deploy/README.md)
- [Bootstrap k3s (Ansible)](../../deploy/kubernetes/bootstrap/README.md)
- [Ранбук Kubernetes-деплоя](../../deploy/kubernetes/README.md)
- [Этап B: эксплуатация и приемка](./operations-stage-b.md)
- [Карта этапа B: bootstrap, Helmfile и releases](./helmfiles-releases-map.md)

## Сеть, безопасность и TLS

- [Сеть этапа B (NetworkPolicy)](./network.md)
- [Edge TLS через cert-manager + Let's Encrypt (HTTP-01)](./edge-tls-acme.md)
- [Ранбук по сертификатам edge](./certificates-runbook.md)

## Резервное копирование и восстановление данных

- [PostgreSQL: backup и restore](./backup-restore.md)

## n8n workflows

- [n8n workflows](../../n8n/workflows/README.md)
