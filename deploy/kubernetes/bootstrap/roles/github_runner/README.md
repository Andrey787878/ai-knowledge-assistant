# github_runner

Роль для установки и настройки self-hosted GitHub Actions runner
на отдельной VM в этапе B. Runner работает как systemd service,
перезапускается после reboot и используется для k3s CD.

## Структура роли

```text
.
├── README.md
├── defaults/main.yml
├── handlers/main.yml
├── templates/
│   └── github-actions-runner.service.j2
└── tasks/
    ├── main.yml
    ├── validate.yml
    ├── install.yml
    ├── configure.yml
    ├── service.yml
    └── verify.yml
```

## Что делает

- Проверяет поддерживаемую ОС (`Debian` family) и валидность параметров.
- Создаёт системного пользователя `github-runner`.
- Устанавливает зависимости: `curl`, `tar`, `jq`, `git`.
- Скачивает GitHub Actions runner pinned версии и распаковывает в
  `/opt/github-runner`. Повторное извлечение происходит только при смене
  версии (маркер `.installed_version`).
- Регистрирует runner в репозитории через `config.sh` (идемпотентно: повторная
  регистрация не выполняется, пока существует `.runner`).
- Создаёт systemd unit `github-actions-runner.service` и включает его.
- Устанавливает CD-инструменты для деплоя в k3s: `kubectl`, `helm`, `helmfile`,
  `sops`, `age`, helm plugin `helm-secrets`.
- При `github_runner_kubeconfig_enabled: true` кладёт kubeconfig на runner
  (`/home/github-runner/.kube/config`) с server, указанным на private endpoint
  k3s API (`https://<k3s private ip>:6443`).
- При `github_runner_kubeconfig_enabled: true` также кладёт `age` private key в
  `/home/github-runner/.config/sops/age/keys.txt`, чтобы CD workflow могли
  расшифровывать SOPS-encrypted Helm values.
- Проверяет:
  - сервис активен и enabled;
  - маркеры регистрации `.runner` и `.credentials` на месте;
  - kubeconfig на месте (когда включён);
  - `SOPS_AGE_KEY_FILE` существует и имеет mode `0600` (когда включён);
  - `kubectl` с runner видит хотя бы один `Ready` node.

## Идемпотентность

- Runner не перерегистрируется каждый прогон: `config.sh` запускается с
  `creates: .runner`, поэтому регистрация выполняется один раз.
- `github_runner_replace_existing: true` удаляет `.runner`/`.credentials`
  перед регистрацией — используется для ротации или пересоздания runner.
- Archive переизвлекается только при смене `github_runner_version`.
- systemd unit рендерится через `template` (идемпотентно).

## Режим

Persistent self-hosted runner as systemd service. Не используется:
ephemeral job runner, autoscaling, runner controller in k8s.

## Labels

По умолчанию (см. `group_vars/github_runners/main.yml`):

- `self-hosted`
- `linux`
- `x64`
- `k3s`
- `prod`
- `deploy`
- `stage-b`

CD workflow использует runs-on: `[self-hosted, linux, x64, k3s, prod, deploy]`.

## Доступ к Kubernetes

Runner деплоит в cluster через kubeconfig. Bootstrap берёт `/etc/rancher/k3s/k3s.yaml`
с k3s host, заменяет server на private IP k3s и кладёт в
`/home/github-runner/.kube/config` (owner `github-runner`, mode `0600`).

Используется admin kubeconfig (CD bootstrap shortcut). Альтернатива —
отдельный service account + cluster-admin binding.

CD workflow использует kubeconfig через `KUBECONFIG=/home/github-runner/.kube/config`.

## Переменные

Ключевые переменные из `defaults/main.yml`:

- `github_runner_enabled`
- `github_runner_version`
- `github_runner_install_dir`
- `github_runner_user` / `github_runner_group`
- `github_runner_repo_url` (репозиторий для регистрации)
- `github_runner_registration_token` (sensitive, из zz-local.yml)
- `github_runner_labels`
- `github_runner_runner_name`
- `github_runner_replace_existing`
- `github_runner_service_name`
- `github_runner_kubeconfig_enabled`
- `github_runner_k3s_kubeconfig_path` / `github_runner_kubeconfig_dest`
- `github_runner_k3s_api_host` (пусто -> берётся из k3s_hosts group)
- `github_runner_sops_age_key` / `github_runner_sops_age_key_file`
- `github_runner_kubectl_version` / `github_runner_helm_version` /
  `github_runner_helmfile_version` / `github_runner_sops_version` /
  `github_runner_age_version` / `github_runner_helm_secrets_version`

Secret-модель для registration token и `age` private key описана в
[inventories/cloud/group_vars/github_runners/zz-local.yml.example](../../inventories/cloud/group_vars/github_runners/zz-local.yml.example)
и в [bootstrap README](../../README.md).

Практический источник значений:

- `github_runner_registration_token`:
  `Settings -> Actions -> Runners -> New self-hosted runner`
- `github_runner_sops_age_key`:
  существующий локальный `~/.config/sops/age/keys.txt`

## Использование

```yaml
- hosts: github_runners
  become: true
  roles:
    - github_runner
```

## Быстрая проверка

```bash
cd deploy/kubernetes/bootstrap
ansible -i inventories/cloud/hosts.yml github_runners -b -m shell -a "systemctl is-active github-actions-runner"
ansible -i inventories/cloud/hosts.yml github_runners -b -u github-runner -m shell -a "kubectl --kubeconfig /home/github-runner/.kube/config get nodes"
```
