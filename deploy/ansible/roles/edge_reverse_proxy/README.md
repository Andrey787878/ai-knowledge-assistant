# edge_reverse_proxy

Роль для развертывания `Nginx` как edge reverse proxy для `n8n` и `Wiki.js` с HTTPS.

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
│   ├── config.yml
│   ├── service.yml
│   └── verify.yml
└── templates/
    ├── _tls_security_headers.j2
    ├── n8n.conf.j2
    └── wiki.conf.j2
```

## Что делает

- Проверяет входные переменные и поддерживаемую ОС.
- Устанавливает `nginx`.
- Создает каталог конфигурации `conf.d`.
- Опционально удаляет дефолтные конфиги nginx.
- Рендерит конфиги:
  - `n8n.conf`
  - `wiki.conf`
  - общий TLS/security snippet
- Проверяет синтаксис `nginx -t`.
- Поднимает сервис nginx в целевое состояние.
- Выполняет verify:
  - HTTP/HTTPS порты слушаются;
  - есть редирект `HTTP -> HTTPS`;
  - `n8n /healthz` и `wiki /healthz` доступны через HTTPS proxy;
  - в HTTPS-ответах есть `HSTS` и базовые security headers.

Порядок выполнения:
`validate -> install -> config -> service -> flush_handlers -> verify`.

## Предусловия

- На edge-хосте уже выполнены роли `common` и `docker_engine`.
- Для полного HTTPS-режима на хосте существуют TLS-файлы:
  - `nginx_rp_tls_cert_path`
  - `nginx_rp_tls_key_path`
  - `nginx_rp_verify_ca_cert_path` (для строгой проверки TLS в verify)
- Upstream-сервисы (`n8n`, `wikijs`) доступны по заданным host/port.
- Для bootstrap HTTP-01 допускается первый запуск в HTTP-only режиме:
  - `nginx_rp_enable_https_server: false`
  - `nginx_rp_require_tls_artifacts: false`
  - `nginx_rp_verify_enabled: false`

## Граница ответственности

`edge_reverse_proxy` отвечает только за runtime reverse proxy (`install/config/service/verify`) и не разворачивает сами backend-сервисы.

## Переменные

- `nginx_rp_*_host` / `nginx_rp_*_port` / `nginx_rp_*_server_name` - upstream и домены.
- `nginx_rp_http_port`, `nginx_rp_https_port` - публичные порты edge.
- `nginx_rp_enable_https_server` - включает/выключает HTTPS server blocks.
- `nginx_rp_require_tls_artifacts` - требовать наличие cert/key в validate.
- `nginx_rp_allowed_client_cidrs` - обязательный allow-list клиентов для `wiki` и `n8n` в `location` блоках nginx.
- `nginx_rp_tls_*` - пути к сертификату и ключу.
- `nginx_rp_proxy_*` и `nginx_rp_n8n_proxy_*` - proxy timeouts/body limits.
- `nginx_rp_hsts_*` - параметры HSTS.
- `nginx_rp_service_*` - состояние сервиса nginx.
- `nginx_rp_verify_local_host`, `nginx_rp_verify_ca_cert_path` - параметры strict verify-блока (TLS-проверка по CA обязательна).

## Использование

```yaml
- hosts: wiki_hosts
  become: true
  roles:
    - edge_reverse_proxy
```

Пример `host_vars/wiki.yml`:

```yaml
nginx_rp_n8n_server_name: n8n.poluyanov.net
nginx_rp_wiki_server_name: wiki.poluyanov.net

nginx_rp_n8n_host: "{{ hostvars['n8n'].private_ip }}"
nginx_rp_n8n_port: 5678

nginx_rp_wiki_host: 127.0.0.1
nginx_rp_wiki_port: 3000

nginx_rp_allowed_client_cidrs:
  - 198.51.100.10/32

nginx_rp_tls_cert_path: /etc/nginx/tls/fullchain.pem
nginx_rp_tls_key_path: /etc/nginx/tls/privkey.pem
nginx_rp_verify_ca_cert_path: /etc/ssl/certs/ca-certificates.crt
```

## Быстрая проверка

SSH-вариант (опционально): для ручного дебага см. [раздел в основном runbook](../../README.md#manual-ssh).

Команды ниже предполагают, что в текущей shell-сессии уже задан `ANSIBLE_VAULT_PASSWORD_FILE` (см. `deploy/ansible/README.md`, шаг 3).

Проверка уровня роли подтверждает запуск nginx, валидный конфиг, HTTPS-редиректы, доступность `healthz` endpoint'ов через HTTPS proxy и наличие HSTS/security headers.

```bash
cd deploy/ansible
ansible -i inventories/cloud/hosts.yml wiki_hosts -b -J -m shell -a "nginx -t"
ansible -i inventories/cloud/hosts.yml wiki_hosts -b -J -m shell -a "systemctl is-active nginx"
ansible -i inventories/cloud/hosts.yml wiki_hosts -b -J -m shell -a "curl -I -H 'Host: wiki.poluyanov.net' http://127.0.0.1/"
ansible -i inventories/cloud/hosts.yml wiki_hosts -b -J -m shell -a "curl --resolve wiki.poluyanov.net:443:127.0.0.1 --cacert /etc/ssl/certs/ca-certificates.crt https://wiki.poluyanov.net/healthz"
ansible -i inventories/cloud/hosts.yml wiki_hosts -b -J -m shell -a "curl --resolve n8n.poluyanov.net:443:127.0.0.1 --cacert /etc/ssl/certs/ca-certificates.crt https://n8n.poluyanov.net/healthz"
```
