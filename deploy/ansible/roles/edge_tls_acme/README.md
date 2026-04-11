# edge_tls_acme

Роль для выпуска и обновления публичного Let's Encrypt сертификата для edge-nginx
на `wiki_hosts` через HTTP-01.

## Структура роли

```text
.
├── README.md
├── defaults/main.yml
├── handlers/main.yml
├── tasks/
│   ├── main.yml
│   ├── validate.yml
│   ├── install.yml
│   └── issue.yml
└── templates/
    └── reload-nginx-hook.sh.j2
```

## Что делает

- Валидирует входные переменные для LE и webroot HTTP-01.
- Устанавливает `certbot`.
- Подготавливает webroot директорию для ACME challenge.
- Выпускает/обновляет SAN сертификат для `wiki` и `n8n` доменов.
- Делает `nginx reload` через handler, если certbot реально обновил сертификат.
- Устанавливает deploy hook для `nginx reload` после renew.
- Проверяет `certbot renew --dry-run`.
- Синхронизирует переменные nginx роли на LE пути сертификата.

## Предусловия

- DNS записи доменов edge уже указывают на публичный IP хоста `wiki` (`wiki_hosts`).
- На edge-хосте открыт `80/tcp` для внешней проверки Let's Encrypt.
- В `edge_reverse_proxy` настроена выдача
  `/.well-known/acme-challenge/*` из `edge_tls_acme_webroot_path` без редиректа.

## HTTP-01 коротко (зачем нужен 80/tcp)

При выпуске/renew сертификата Let's Encrypt проверяет владение доменом через HTTP-01:

1. `certbot` кладет challenge-файл в
   `{{ edge_tls_acme_webroot_path }}/.well-known/acme-challenge/<token>`.
2. Let's Encrypt делает запрос:
   `http://<domain>/.well-known/acme-challenge/<token>`.
3. Если ответ совпал с ожидаемым challenge, сертификат выпускается/продлевается.

В текущем nginx-конфиге `80/tcp` нужен для challenge и redirect:

- `/.well-known/acme-challenge/*` отдается из webroot,
- остальные HTTP-запросы перенаправляются на HTTPS (`301`).

## Граница ответственности

Роль отвечает только за публичный edge TLS.

## Использование

```yaml
- hosts: wiki_hosts
  become: true
  roles:
    - edge_tls_acme
    - edge_reverse_proxy
```

## Быстрая проверка

SSH-вариант (опционально): для ручного дебага см. [раздел в основном runbook](../../README.md#manual-ssh).

Команды ниже предполагают, что в текущей shell-сессии уже задан `ANSIBLE_VAULT_PASSWORD_FILE` (см. `deploy/ansible/README.md`, шаг 3).

```bash
cd deploy/ansible
ansible -i inventories/cloud/hosts.yml wiki_hosts -b -J -m shell -a "certbot --version"
ansible -i inventories/cloud/hosts.yml wiki_hosts -b -J -m shell -a "certbot certificates"
ansible -i inventories/cloud/hosts.yml wiki_hosts -b -J -m shell -a "find /etc/letsencrypt/live -maxdepth 2 -name fullchain.pem -size +0c -print"
ansible -i inventories/cloud/hosts.yml wiki_hosts -b -J -m shell -a "systemctl is-active nginx"
ansible -i inventories/cloud/hosts.yml wiki_hosts -b -J -m shell -a "curl -I -H 'Host: wiki.poluyanov.net' http://127.0.0.1/"
```
