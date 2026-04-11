# Edge TLS через Let's Encrypt (HTTP-01)

## Область

Документ описывает публичный TLS для edge-хоста `wiki` (`wiki_hosts`) в текущем Ansible-этапе.

Для команд ниже предполагается, что в текущей shell-сессии уже задан
`ANSIBLE_VAULT_PASSWORD_FILE`
(см. [deploy/ansible/README.md, шаг 3](../../deploy/ansible/README.md#step-3)).

## Цель

- Browser-trusted сертификаты для `wiki` и `n8n` доменов.
- Автоматический renew без ручного перевыпуска.
- Привязка edge proxy к актуальным LE путям cert/key.

## Что реализовано

Роль `edge_tls_acme` на `wiki_hosts`:

1. устанавливает `certbot`,
2. готовит webroot для ACME challenge,
3. выпускает/обновляет SAN сертификат,
4. ставит deploy hook для `nginx reload`,
5. синхронизирует `nginx_rp_tls_cert_path` и `nginx_rp_tls_key_path`.

`site.yml` использует bootstrap-порядок:

1. `edge_reverse_proxy` в HTTP-only режиме для ACME challenge,
2. `edge_tls_acme` для выпуска сертификата,
3. повторный `edge_reverse_proxy` в полном HTTPS-режиме.

## Домены и DNS

Для текущего контура:

- `wiki.poluyanov.net`
- `n8n.poluyanov.net`

Обе записи должны указывать на публичный IP `wiki` хоста.

## Предусловия HTTP-01

- DNS записи `wiki.poluyanov.net` и `n8n.poluyanov.net` указывают на `wiki` хост.
- На `wiki` хосте открыт `80/tcp` из интернета (`0.0.0.0/0`) для challenge.
- В `edge_reverse_proxy` есть location `/.well-known/acme-challenge/*` без redirect.

## Как работает ACME HTTP-01

1. Let's Encrypt (ACME CA) создает challenge для конкретного домена.
2. `certbot` на edge-хосте получает challenge и размещает challenge-файл в webroot
   (в проекте по умолчанию `/var/www/letsencrypt`):
   `/var/www/letsencrypt/.well-known/acme-challenge/<token>`.
3. Nginx на `80/tcp` отдает только содержимое `/.well-known/acme-challenge/*` из webroot,
   а все остальные HTTP-запросы переводит на HTTPS (`301`).
4. Let's Encrypt делает `GET http://<domain>/.well-known/acme-challenge/<token>`
   и сверяет ответ с ожидаемым значением challenge.
5. При совпадении домен считается подтвержденным, сертификат выпускается/продлевается.

Важно:

- `80/tcp` должен быть доступен извне именно для HTTP-01 проверки.
- Это не "полноценный HTTP сайт": для обычного трафика на `80` действует redirect на `443`.
- Проверка владения доменом выполняется на основании DNS + успешного HTTP challenge-response.

## Ключевые переменные (host_vars/wiki.yml)

- `edge_tls_acme_email: andrey@poluyanov.net`
- `edge_tls_acme_primary_domain: wiki.poluyanov.net`
- `edge_tls_acme_additional_domains: [n8n.poluyanov.net]`
- `edge_tls_acme_webroot_path: /var/www/letsencrypt`
- `edge_tls_acme_use_staging: false`
- `edge_tls_acme_force_renew: false`

Nginx пути:

- `nginx_rp_tls_cert_path: /etc/letsencrypt/live/wiki.poluyanov.net/fullchain.pem`
- `nginx_rp_tls_key_path: /etc/letsencrypt/live/wiki.poluyanov.net/privkey.pem`

## Запуск

```bash
cd deploy/ansible
ansible-playbook -i inventories/cloud/hosts.yml playbooks/bootstrap_python.yml
ansible-playbook -i inventories/cloud/hosts.yml playbooks/site.yml
```

## Проверка

```bash
cd deploy/ansible
ansible-playbook -i inventories/cloud/hosts.yml playbooks/smoke.yml
```

Через Ansible (предпочтительно):

```bash
ansible -i inventories/cloud/hosts.yml wiki_hosts -b -J -m shell -a "certbot certificates"
ansible -i inventories/cloud/hosts.yml wiki_hosts -b -J -m shell -a "certbot renew --dry-run"
```

На edge-хосте (ручной debug):

```bash
sudo certbot certificates
sudo certbot renew --dry-run
```

Проверка HTTP-01 маршрута вручную:

```bash
ansible -i inventories/cloud/hosts.yml wiki_hosts -b -J -m shell -a \
"mkdir -p /var/www/letsencrypt/.well-known/acme-challenge && \
echo ok > /var/www/letsencrypt/.well-known/acme-challenge/ping && \
curl -sS -H 'Host: wiki.poluyanov.net' http://127.0.0.1/.well-known/acme-challenge/ping && echo && \
curl -sS -H 'Host: n8n.poluyanov.net'  http://127.0.0.1/.well-known/acme-challenge/ping && echo"
```
