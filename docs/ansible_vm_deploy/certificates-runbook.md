# Ранбук: сертификаты edge (Let's Encrypt)

## Область
Документ описывает эксплуатационный процесс выпуска, продления и проверки edge TLS сертификатов.

Релевантные роли:

- `edge_tls_acme`
- `edge_reverse_proxy`

Релевантные домены:

- `wiki.poluyanov.net`
- `n8n.poluyanov.net`

Для команд ниже предполагается, что в текущей shell-сессии уже задан
`ANSIBLE_VAULT_PASSWORD_FILE`
(см. [deploy/ansible/README.md, шаг 3](../../deploy/ansible/README.md#step-3)).

## Где лежат сертификаты

На `wiki` хосте (`wiki_hosts`):

- `nginx_rp_tls_cert_path` -> `/etc/letsencrypt/live/wiki.poluyanov.net/fullchain.pem`
- `nginx_rp_tls_key_path` -> `/etc/letsencrypt/live/wiki.poluyanov.net/privkey.pem`

CA bundle для локальной проверки:

- `nginx_rp_verify_ca_cert_path` -> `/etc/ssl/certs/ca-certificates.crt`

## Выпуск и renew

`edge_tls_acme` автоматически:

1. ставит certbot,
2. использует HTTP-01 challenge через webroot,
3. выпускает SAN cert,
4. на renew выполняет `nginx reload` через deploy hook.

Обычный запуск:

```bash
cd deploy/ansible
ansible-playbook -i inventories/cloud/hosts.yml playbooks/bootstrap_python.yml
ansible-playbook -i inventories/cloud/hosts.yml playbooks/site.yml
```

## Переменные

Минимально важные (`host_vars/wiki.yml`):

- `edge_tls_acme_email`
- `edge_tls_acme_primary_domain`
- `edge_tls_acme_additional_domains`
- `edge_tls_acme_webroot_path`
- `edge_tls_acme_use_staging`
- `edge_tls_acme_force_renew`

## Проверка

### Через Ansible smoke

```bash
cd deploy/ansible
ansible-playbook -i inventories/cloud/hosts.yml playbooks/smoke.yml
```

Smoke проверяет:

- доступность `/.well-known/acme-challenge/*` по HTTP без redirect,
- redirect `HTTP -> HTTPS`,
- `HTTPS /healthz` для `wiki` и `n8n`,
- срок действия edge сертификата (`openssl x509 -checkend`).

### Через Ansible (предпочтительно)

```bash
cd deploy/ansible
ansible -i inventories/cloud/hosts.yml wiki_hosts -b -J -m shell -a "certbot certificates"
ansible -i inventories/cloud/hosts.yml wiki_hosts -b -J -m shell -a "certbot renew --dry-run"
```

### На edge-хосте (ручной debug)

```bash
sudo certbot certificates
sudo certbot renew --dry-run
```

## Что делать при проблемах

1. Проверьте DNS A/AAAA записи доменов на edge IP.
2. Проверьте, что `80/tcp` открыт для HTTP-01 challenge.
3. Проверьте, что nginx отдает `/.well-known/acme-challenge/*` из webroot без redirect.
4. Проверьте логи certbot и nginx.
5. Повторно примените `site.yml`.
6. Повторно запустите `smoke.yml`.

## Инцидентный rollback

Если edge cert временно недоступен:

1. восстановить рабочий cert/key в `nginx_rp_tls_*` пути,
2. сделать `nginx -t && systemctl reload nginx`,
3. подтвердить `smoke.yml`.
