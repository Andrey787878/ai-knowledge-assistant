# Этап A (4 VM): деплой через Terraform + Ansible + Docker Compose

Единая точка входа в документацию этапа A, где:

- Terraform отвечает за создание инфраструктуры и настройку облачных ресурсов,
- Ansible отвечает за настройку хостов и деплой сервисов,
- Docker Compose отвечает за запуск и жизненный цикл контейнеров на хостах.

## Запуск и приемка

- [Terraform: инфраструктура](../../deploy/terraform/ansible_deploy/README.md)
- [Ранбук Ansible-деплоя](../../deploy/ansible/README.md)
- [Этап A: эксплуатация и приемка](./operations-stage-a.md)
- [Карта Ansible: роли и playbook](./roles-playbooks-map.md)

## Сеть, безопасность и TLS

- [Сеть Ansible-деплоя](./network.md)
- [Схема сети](./diagrams/network-topolog.png)
- [Публичный edge TLS через Let's Encrypt (HTTP-01)](./edge-tls-acme.md)
- [Ранбук по сертификатам edge](./certificates-runbook.md)

## Резервное копирование и восстановление данных

- [PostgreSQL: резервное копирование и восстановление](./backup-restore.md)

## n8n workflows

- [n8n workflows](../../n8n/workflows/README.md)
