# Эксплуатация и приемка

## Область

Документ описывает эксплуатационный процесс и критерии приемки.

## Порядок этапа A

1. Terraform: `init -> plan -> apply` в `deploy/terraform/ansible_deploy`.
2. Синхронизация inventory: `sync_inventory.sh` (terraform output -> `deploy/ansible/inventories/cloud/hosts.yml`).
3. `playbooks/bootstrap_python.yml` на все VM.
4. `playbooks/site.yml` (основной Ansible-деплой).
5. `playbooks/smoke.yml` (приемка).

## Внутренний порядок `site.yml`

1. `common`, `docker_engine`, `firewall` на все VM.
2. `postgres_server` + `postgres_backup` на `db_hosts`.
3. `ollama_server` на `ollama_hosts`.
4. `n8n_stack` на `n8n_hosts`.
5. `wikijs_server` + `edge_reverse_proxy` (HTTP bootstrap) +
   `edge_tls_acme` + `edge_reverse_proxy` (финальный HTTPS) на `wiki_hosts`.

Полная карта ролей и задач:
[roles-playbooks-map.md](./roles-playbooks-map.md).

## Если Ansible игнорирует `ansible.cfg`

Если при запуске появляется warning про `world writable directory`
и Ansible не подхватывает `ansible.cfg`, перед запуском экспортируйте:

```bash
cd deploy/ansible
export ANSIBLE_ROLES_PATH="$(pwd)/roles"
export ANSIBLE_LOCAL_TEMP="$(pwd)/.ansible/tmp"
export ANSIBLE_VAULT_PASSWORD_FILE="${ANSIBLE_VAULT_PASSWORD_FILE:-~/.ansible/vault-pass.txt}"
```

Полный ранбук:
[deploy/ansible/README.md](../../deploy/ansible/README.md).

## Область smoke-проверок этапа A

Текущий `playbooks/smoke.yml` покрывает:

- HTTP-01 challenge path `/.well-known/acme-challenge/*`,
- edge redirect `HTTP -> HTTPS`,
- edge `HTTPS /healthz` для `wiki` и `n8n`,
- связность `n8n -> ollama`,
- policy-check (включая ожидаемое поведение для `db -> n8n:5678`),
- срок действия edge сертификата,
- e2e `agent-query` (включен по умолчанию).

## Release gate

Релиз этапа A успешен только если:

1. `playbooks/site.yml` завершился с `failed=0`.
2. `playbooks/smoke.yml` завершился с `failed=0`.
3. Backup/restore ранбук подтвержден практическим прогоном.

## Backup/Restore

Смотрите отдельный ранбук:
[backup-restore.md](./backup-restore.md).
