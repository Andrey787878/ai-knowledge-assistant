# Этап A: 4 VM, Terraform, Ansible и Docker Compose

Этот раздел собирает документацию по контуру на виртуальных машинах. Здесь
описаны запуск инфраструктуры, деплой сервисов, сеть, сертификаты и
операционные процедуры для этапа A.

## Что описывает этот раздел

Этап A разворачивает четыре виртуальные машины и поднимает сервисы через
Docker Compose:

- `wiki` (edge/reverse proxy + Wiki.js)
- `db` (PostgreSQL)
- `n8n` (web + worker + redis)
- `ollama` (LLM runtime)

## Основные документы

### Запуск и приемка

- [Terraform: инфраструктура этапа A](../../deploy/terraform/ansible_deploy/README.md)
- [Ранбук Ansible-деплоя](../../deploy/ansible/README.md)
- [Эксплуатация и приемка](./operations.md)
- [Карта ролей и плейбуков](./roles-playbooks-map.md)

### Сеть и безопасность

- [Сеть Ansible-деплоя](./network.md)
- [Edge TLS и ACME HTTP-01](./edge-tls-acme.md)
- [Ранбук по сертификатам](./certificates-runbook.md)

### Данные

- [PostgreSQL: резервное копирование и восстановление](./backup-restore.md)
