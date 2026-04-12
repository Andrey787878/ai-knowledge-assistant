# k3s_server

Роль для установки и проверки single-node k3s на VM в bootstrap-этапе.

## Структура роли

```text
.
├── README.md
├── defaults/main.yml
└── tasks/
    ├── main.yml
    ├── validate.yml
    ├── install.yml
    └── verify.yml
```

## Что делает

- Проверяет поддерживаемую ОС (`Debian` family) и валидность параметров роли.
- Определяет архитектуру хоста и скачивает релизные артефакты k3s для pinned версии:
  - бинарник `k3s`,
  - официальный checksum-файл `sha256sum-<arch>.txt`.
- Проверяет checksum бинарника перед установкой.
- Устанавливает проверенный бинарник в `k3s_binary_install_dir`.
- Скачивает install script `https://get.k3s.io` и запускает его с `INSTALL_K3S_SKIP_DOWNLOAD=true`.
- Передает флаги через `INSTALL_K3S_EXEC`:
  - `server`
  - `--write-kubeconfig-mode`
  - `--disable traefik` (опционально)
  - дополнительные `k3s_server_extra_args`
- Гарантирует, что сервис `k3s` включен и запущен.
- Проверяет:
  - порт API `6443` доступен;
  - `k3s` сервис активен;
  - kubeconfig существует;
  - node переходит в `Ready`.

## Граница ответственности

Роль управляет только установкой и проверкой k3s server на хосте.

Роль не управляет firewall, ingress/cert-manager и деплоем приложений.

## Переменные

Ключевые переменные из `defaults/main.yml`:

- `k3s_supported_os_families`
- `k3s_install_script_url`
- `k3s_release_download_base_url`
- `k3s_version`
- `k3s_binary_install_dir`
- `k3s_download_dir`
- `k3s_arch_map`
- `k3s_service_name`
- `k3s_kubeconfig_path`
- `k3s_write_kubeconfig_mode`
- `k3s_disable_traefik`
- `k3s_server_extra_args`
- `k3s_wait_api_timeout`
- `k3s_wait_node_ready_retries`
- `k3s_wait_node_ready_delay`

## Использование

```yaml
- hosts: k3s_hosts
  become: true
  roles:
    - k3s_server
```

## Быстрая проверка

```bash
cd deploy/kubernetes/bootstrap
ansible -i inventories/cloud/hosts.yml k3s_hosts -b -m shell -a "systemctl is-active k3s"
ansible -i inventories/cloud/hosts.yml k3s_hosts -b -m shell -a "kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get nodes"
```
