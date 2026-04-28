# Этап A (4 VM): документация Terraform + Ansible + Docker Compose

Единая точка входа в документацию этапа A.

## Назначение

Этап A разворачивает 4 VM и сервисы в Docker Compose:

- `wiki` (edge/reverse proxy + Wiki.js)
- `db` (PostgreSQL)
- `n8n` (web + worker + redis)
- `ollama` (LLM runtime)

## Запуск и приемка

- [Terraform: инфраструктура этапа A](../../deploy/terraform/ansible_deploy/README.md)
- [Ранбук Ansible-деплоя](../../deploy/ansible/README.md)
- [Эксплуатация и приемка](./operations.md)
- [Карта ролей и playbook](./roles-playbooks-map.md)

## Сеть и безопасность

![Схема сети этапа A](./diagrams/network-topology.png)

- [Сеть Ansible-деплоя](./network.md)
- [Edge TLS и ACME HTTP-01](./edge-tls-acme.md)
- [Ранбук по сертификатам](./certificates-runbook.md)

## Данные

- [PostgreSQL: резервное копирование и восстановление](./backup-restore.md)
