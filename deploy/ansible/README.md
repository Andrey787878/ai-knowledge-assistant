# Этап A (4 VM): Ansible runbook

Единая точка запуска для Ansible-этапа (4 VM + Docker Compose).

Индекс документации этапа A: [README этапа A](../../docs/ansible_vm_deploy/README.md)

![Архитектура и сеть этапа A](../../docs/ansible_vm_deploy/diagrams/network-topology.png)

## Назначение

Этот этап разворачивает инфраструктуру на 4 VM:

- `wiki` (edge/bastion, reverse proxy, Wiki.js)
- `db` (PostgreSQL)
- `n8n` (web + worker + redis)
- `ollama` (LLM runtime)

## Быстрый старт

```bash
cd deploy/ansible

cp inventories/cloud/hosts.yml.example inventories/cloud/hosts.yml
cp inventories/cloud/group_vars/all/zz-local.yml.example inventories/cloud/group_vars/all/zz-local.yml
cp inventories/cloud/group_vars/all/vault.yml.example inventories/cloud/group_vars/all/vault.yml

mkdir -p ~/.ansible
printf '%s\n' '<your-vault-password>' > ~/.ansible/vault-pass.txt
chmod 600 ~/.ansible/vault-pass.txt

export ANSIBLE_ROLES_PATH="$(pwd)/roles"
export ANSIBLE_LOCAL_TEMP="$(pwd)/.ansible/tmp"
export ANSIBLE_SSH_PRIVATE_KEY_FILE="${ANSIBLE_SSH_PRIVATE_KEY_FILE:-~/.ssh/ansible_deploy}"
export ANSIBLE_VAULT_PASSWORD_FILE="${ANSIBLE_VAULT_PASSWORD_FILE:-~/.ansible/vault-pass.txt}"
export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_FORKS=10
export ANSIBLE_TIMEOUT=30

ansible-vault edit inventories/cloud/group_vars/all/vault.yml
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventories/cloud/hosts.yml playbooks/bootstrap_python.yml
ansible-playbook -i inventories/cloud/hosts.yml playbooks/site.yml
ansible-playbook -i inventories/cloud/hosts.yml playbooks/smoke.yml
```

## Предусловия

- Terraform Этап A выполнен (VM и сеть созданы).
- Заполнены реальные адреса и CIDR в:
  - `inventories/cloud/hosts.yml`
  - `inventories/cloud/group_vars/all/zz-local.yml`
- Секреты заполнены в `inventories/cloud/group_vars/all/vault.yml` (Ansible Vault).
- Установлен `ansible-core` и коллекции из `requirements.yml`.

## Подготовка секретов

Ключевые связки значений в `vault.yml`:

- `n8n_postgres_password = postgres_n8n_password`
- `wikijs_postgres_password = postgres_wiki_password`

Быстрая генерация секретов:

```bash
openssl rand -base64 36 | tr -d '\n'
openssl rand -hex 32
```

Проверка, что vault читается:

```bash
ansible-vault view inventories/cloud/group_vars/all/vault.yml >/dev/null && echo "vault decrypt: ok"
```

## Порядок запуска

```bash
cd deploy/ansible
ansible-playbook -i inventories/cloud/hosts.yml playbooks/bootstrap_python.yml
ansible-playbook -i inventories/cloud/hosts.yml playbooks/site.yml
ansible-playbook -i inventories/cloud/hosts.yml playbooks/smoke.yml
```

Отключить e2e-часть в smoke при необходимости:

```bash
ansible-playbook -i inventories/cloud/hosts.yml playbooks/smoke.yml \
  -e '{"smoke_agent_e2e_enabled": false}'
```

## Проверка после деплоя

```bash
ansible-playbook -i inventories/cloud/hosts.yml playbooks/smoke.yml
```

Критерий готовности:

- `site.yml` и `smoke.yml` завершены с `failed=0`.

## Операционные команды

Разовый backup PostgreSQL:

```bash
ansible-playbook -i inventories/cloud/hosts.yml playbooks/backup_postgres.yml
```

Restore PostgreSQL:

```bash
ansible-playbook -i inventories/cloud/hosts.yml playbooks/restore_postgres.yml \
  -e "postgres_restore_confirm=YES" \
  -e "postgres_restore_source_dir=/var/backups/ai-agent/postgres/<timestamp>" \
  -e "postgres_restore_with_globals=false"
```

## Частые проблемы

`the role 'common' was not found`:

- экспортируйте `ANSIBLE_ROLES_PATH="$(pwd)/roles"`.

`world writable directory` и игнор `ansible.cfg`:

- запускайте с экспортами `ANSIBLE_ROLES_PATH`, `ANSIBLE_LOCAL_TEMP`,
  `ANSIBLE_HOST_KEY_CHECKING`, `ANSIBLE_FORKS`, `ANSIBLE_TIMEOUT`.

`Failed to update apt cache` на private VM:

- проверьте route `0.0.0.0/0 -> NAT` и egress правила.

## Связанная документация

- [Индекс Ansible VM документации](../../docs/ansible_vm_deploy/README.md)
- [Карта ролей и playbook](../../docs/ansible_vm_deploy/roles-playbooks-map.md)
- [Эксплуатация и приемка](../../docs/ansible_vm_deploy/operations.md)
- [Сеть](../../docs/ansible_vm_deploy/network.md)
- [Edge TLS и ACME HTTP-01](../../docs/ansible_vm_deploy/edge-tls-acme.md)
- [Ранбук по сертификатам](../../docs/ansible_vm_deploy/certificates-runbook.md)
- [Резервное копирование и восстановление PostgreSQL](../../docs/ansible_vm_deploy/backup-restore.md)
