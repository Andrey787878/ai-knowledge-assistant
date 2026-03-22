# nginx_reverse_proxy

Роль разворачивает `Nginx` как edge reverse proxy для `n8n` и `Wiki.js` с HTTPS.

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
  - `n8n /healthz` доступен через proxy;
  - `wiki /` доступен через proxy.

Порядок выполнения:
`validate -> install -> config -> service -> flush_handlers -> verify`.

## Предусловия

- На edge-хосте уже выполнены роли `base` и `docker_engine`.
- На хосте существуют TLS-файлы:
  - `nginx_rp_tls_cert_path`
  - `nginx_rp_tls_key_path`
- Upstream-сервисы (`n8n`, `wikijs`) доступны по заданным host/port.

## Граница ответственности

`nginx_reverse_proxy` отвечает только за runtime reverse proxy (`install/config/service/verify`) и не разворачивает сами backend-сервисы.

## Группы переменных

- `nginx_rp_*_host` / `nginx_rp_*_port` / `nginx_rp_*_server_name` - upstream и домены.
- `nginx_rp_http_port`, `nginx_rp_https_port` - публичные порты edge.
- `nginx_rp_tls_*` - пути к сертификату и ключу.
- `nginx_rp_proxy_*` и `nginx_rp_n8n_proxy_*` - proxy timeouts/body limits.
- `nginx_rp_hsts_*` - параметры HSTS.
- `nginx_rp_service_*` - состояние сервиса nginx.
- `nginx_rp_verify_*` - поведение verify-блока.

## Использование

```yaml
- hosts: edge_hosts
  become: true
  roles:
    - nginx_reverse_proxy
```

Пример `host_vars/edge.yml`:

```yaml
nginx_rp_n8n_server_name: n8n.example.com
nginx_rp_wiki_server_name: wiki.example.com

nginx_rp_n8n_host: "{{ hostvars['n8n'].private_ip }}"
nginx_rp_n8n_port: 5678

nginx_rp_wiki_host: "{{ hostvars['wiki'].private_ip }}"
nginx_rp_wiki_port: 3000

nginx_rp_tls_cert_path: /etc/nginx/tls/fullchain.pem
nginx_rp_tls_key_path: /etc/nginx/tls/privkey.pem
```

## Проверка

Проверка уровня роли подтверждает запуск nginx, валидный конфиг, HTTPS-редиректы и доступность backend endpoint'ов через reverse proxy.

```bash
nginx -t
systemctl is-active nginx
curl -I -H 'Host: wiki.example.com' http://127.0.0.1/
curl -k -H 'Host: n8n.example.com' https://127.0.0.1/healthz
```
