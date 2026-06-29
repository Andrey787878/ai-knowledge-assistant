# Этап B (k3s): ранбук Ansible bootstrap

Пошаговый ранбук для первого и повторного запуска bootstrap-этапа `k3s`.
Документ покрывает подготовку single-node `k3s`-VM и, при необходимости,
отдельной VM для self-hosted GitHub Actions runner: базовую настройку хоста,
firewall, установку `k3s`, регистрацию runner и smoke-проверки.

Индекс этапной документации: [README этапа B](../../../docs/kubernetes_deploy/README.md)

## Быстрый старт

```bash
# Подготовьте инфраструктуру Terraform и inventory
cd deploy/terraform/k3s_deploy
bash scripts/sync_inventory.sh

# Перейдите в bootstrap
cd ../../kubernetes/bootstrap

# Подготовьте локальные файлы
cp -n inventories/cloud/group_vars/all/zz-local.yml.example inventories/cloud/group_vars/all/zz-local.yml
cp -n inventories/cloud/group_vars/github_runners/zz-local.yml.example inventories/cloud/group_vars/github_runners/zz-local.yml

# Экспортируйте env для стабильного запуска
export ANSIBLE_ROLES_PATH="$(pwd)/roles"
export ANSIBLE_LOCAL_TEMP="$(pwd)/.ansible/tmp"
export ANSIBLE_SSH_PRIVATE_KEY_FILE="${ANSIBLE_SSH_PRIVATE_KEY_FILE:-~/.ssh/k3s_deploy}"
export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_FORKS=10
export ANSIBLE_TIMEOUT=30
mkdir -p .ansible/tmp

# Установите коллекции
ansible-galaxy collection install -r requirements.yml

# Прогон
ansible-playbook -i inventories/cloud/hosts.yml playbooks/bootstrap_python.yml
ansible-playbook -i inventories/cloud/hosts.yml playbooks/site.yml
ansible-playbook -i inventories/cloud/hosts.yml playbooks/smoke.yml

# Получите kubeconfig на локальную машину
bash scripts/pull_kubeconfig.sh
```

Если в Terraform включен `runner_enabled: true`, тот же `site.yml` дополнительно
настроит host group `github_runners` и поднимет self-hosted GitHub Actions
runner для доставки изменений в этапах B/C.

## Связанная документация

- [Terraform инфраструктура этапа B](../../terraform/k3s_deploy/README.md)
- [Индекс документации этапа B](../../../docs/kubernetes_deploy/README.md)

## Оглавление

- [Критерии готовности](#definition-of-done)
- [Подготовьте inventory](#step-1)
- [Подготовьте локальные файлы из `.example`](#step-2)
- [Экспортируйте env для стабильного запуска](#step-3)
- [Установите коллекции](#step-4)
- [Синтаксис перед прогоном](#step-5)
- [Порядок запуска](#step-6)
- [Получите kubeconfig на локальную машину](#step-7)
- [Частые ошибки и быстрые фиксы](#step-8)

<a id="definition-of-done"></a>

## Критерии готовности

- `ansible-playbook ... playbooks/site.yml` завершился с `failed=0`.
- `ansible-playbook ... playbooks/smoke.yml` завершился с `failed=0`.
- `kubectl get nodes` показывает `Ready` для single-node k3s.
- если включен `runner_enabled`, runner host зарегистрирован в GitHub и
  сервис `github-actions-runner` находится в `active`.

<a id="step-1"></a>

## Подготовьте inventory

Рекомендуемый путь: генерировать inventory из Terraform output.

```bash
cd deploy/terraform/k3s_deploy
bash scripts/sync_inventory.sh
```

Файл, который должен появиться/обновиться:

- `deploy/kubernetes/bootstrap/inventories/cloud/hosts.yml`

Альтернатива (ручной режим):

```bash
cd deploy/kubernetes/bootstrap
cp inventories/cloud/hosts.yml.example inventories/cloud/hosts.yml
```

В `inventories/cloud/hosts.yml` заполните:

- `ansible_host` - публичный IP VM `k3s`.
- `private_ip` - внутренний IP VM `k3s`.
- при наличии runner:
  - `ansible_host` - внутренний IP VM `runner`;
  - `private_ip` - внутренний IP VM `runner`.

`github_runners` при этом должны лежать внутри inventory group
`private_hosts`: именно она добавляет `ProxyJump` через публичный `k3s`.

<a id="step-2"></a>

## Подготовьте локальные файлы из `.example`

```bash
cd deploy/kubernetes/bootstrap

cp -n inventories/cloud/group_vars/all/zz-local.yml.example inventories/cloud/group_vars/all/zz-local.yml
cp -n inventories/cloud/group_vars/github_runners/zz-local.yml.example inventories/cloud/group_vars/github_runners/zz-local.yml
```

Что заполняем:

- `inventories/cloud/group_vars/all/zz-local.yml`:
  - `firewall_admin_ssh_sources` для `22/tcp` на публичном `k3s`.
  - `kube_api_allowed_cidrs` для внешнего admin-доступа к `6443/tcp`.
  - `edge_allowed_client_cidrs` для `443/tcp`.
  - при необходимости локально переопределить `k3s_server_tls_sans`.
  - опционально `edge_http_cidrs` для `80/tcp` (если хотите переопределить).
  - при необходимости локально переопределить `k3s_secrets_encryption_enabled`
    (по умолчанию уже `true` в `group_vars/all/main.yml`).
- `inventories/cloud/group_vars/github_runners/zz-local.yml`:
  - `github_runner_registration_token`;
  - `github_runner_sops_age_key`;
  - при ротации runner: `github_runner_replace_existing: true`.

Если включен runner, его доступ к Kubernetes API не зависит от
`kube_api_allowed_cidrs`. Для runner Terraform автоматически добавляет
отдельное SG-правило на `k3s:6443` по private IP runner VM. На уровне host
firewall это тоже делается автоматически: `k3s_hosts/main.yml` собирает
effective allow-list для `6443/tcp`, который включает и внешние admin CIDR, и
private `/32` адреса из inventory group `github_runners`. Ручной дописки runner
IP в `k3s_hosts/zz-local.yml` не требуется.

Для runner не нужно отдельно задавать SSH CIDR: host firewall и cloud SG
разрешают `22/tcp` только от private IP `k3s`, а администраторский доступ идет
через `ProxyJump`.

По умолчанию `edge_http_cidrs` задается в роли firewall как `0.0.0.0/0`
(нужно для HTTP-01 challenge и HTTP->HTTPS redirect).

Файл `zz-local.yml` локальный и не должен коммититься.

Secret-модель runner проста: bootstrap использует short-lived registration
token из GitHub только во время первой регистрации (или при явной
перерегистрации через `github_runner_replace_existing: true`), после чего
runner сохраняет long-lived credential локально в `.credentials`.

Это значит:

- при первом bootstrap нужен свежий `github_runner_registration_token`;
- при обычных повторных прогонах bootstrap новый token не нужен, если runner уже
  зарегистрирован;
- для ротации нужно получить fresh token в GitHub UI, положить его в
  `group_vars/github_runners/zz-local.yml` и повторно прогнать bootstrap с
  `github_runner_replace_existing: true`.

Для deploy в Kubernetes этого недостаточно: runner также должен иметь
`github_runner_sops_age_key`, чтобы `helmfile` и `helm-secrets` могли
расшифровывать `*.enc.yaml` values во время CD. Bootstrap кладет ключ в
`/home/github-runner/.config/sops/age/keys.txt` с правами `0600`.

Как получить оба значения:

```bash
# 1. GitHub runner registration token
# Repo -> Settings -> Actions -> Runners -> New self-hosted runner
# либо через GitHub CLI:
gh api \
  --method POST \
  /repos/Andrey787878/ai-knowledge-assistant/actions/runners/registration-token \
  --jq '.token'

# 2. Existing SOPS age private key from your local workstation
cat ~/.config/sops/age/keys.txt
```

В `github_runner_sops_age_key` нужно положить именно строку
`AGE-SECRET-KEY-...`, которая уже используется для расшифровки проектных
`*.enc.yaml`.

<a id="step-3"></a>

## Экспортируйте env для стабильного запуска

Если Ansible пишет warning про `world writable directory` и игнорирует `ansible.cfg`, используйте:

```bash
cd deploy/kubernetes/bootstrap

export ANSIBLE_ROLES_PATH="$(pwd)/roles"
export ANSIBLE_LOCAL_TEMP="$(pwd)/.ansible/tmp"
export ANSIBLE_SSH_PRIVATE_KEY_FILE="${ANSIBLE_SSH_PRIVATE_KEY_FILE:-~/.ssh/k3s_deploy}"
export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_FORKS=10
export ANSIBLE_TIMEOUT=30

mkdir -p .ansible/tmp
```

Проверка:

```bash
echo "$ANSIBLE_ROLES_PATH"
echo "$ANSIBLE_LOCAL_TEMP"
echo "$ANSIBLE_SSH_PRIVATE_KEY_FILE"
```

<a id="step-4"></a>

## Установите коллекции

```bash
cd deploy/kubernetes/bootstrap
ansible-galaxy collection install -r requirements.yml
```

<a id="step-5"></a>

## Синтаксис перед прогоном

```bash
cd deploy/kubernetes/bootstrap
ansible-playbook -i inventories/cloud/hosts.yml playbooks/bootstrap_python.yml --syntax-check
ansible-playbook -i inventories/cloud/hosts.yml playbooks/site.yml --syntax-check
ansible-playbook -i inventories/cloud/hosts.yml playbooks/smoke.yml --syntax-check
```

<a id="step-6"></a>

## Порядок запуска

```bash
cd deploy/kubernetes/bootstrap

ansible-playbook -i inventories/cloud/hosts.yml playbooks/bootstrap_python.yml
ansible-playbook -i inventories/cloud/hosts.yml playbooks/site.yml
ansible-playbook -i inventories/cloud/hosts.yml playbooks/smoke.yml
```

Ручные проверки после smoke:

```bash
ansible -i inventories/cloud/hosts.yml k3s_hosts -b -m shell -a "systemctl is-active k3s"
ansible -i inventories/cloud/hosts.yml k3s_hosts -b -m shell -a "kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get nodes -o wide"
ansible -i inventories/cloud/hosts.yml k3s_hosts -b -m shell -a "kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n kube-system get pods -o wide"
ansible -i inventories/cloud/hosts.yml k3s_hosts -b -m shell -a "k3s secrets-encrypt status"
```

Если `runner_enabled: true`, дополнительно проверьте runner:

```bash
ansible -i inventories/cloud/hosts.yml github_runners -b -m shell -a "systemctl is-active github-actions-runner"
ansible -i inventories/cloud/hosts.yml github_runners -b -u github-runner -m shell -a "kubectl --kubeconfig /home/github-runner/.kube/config get nodes"
```

<a id="step-7"></a>

## Получите kubeconfig на локальную машину

```bash
cd deploy/kubernetes/bootstrap
bash scripts/pull_kubeconfig.sh
```

По умолчанию kubeconfig сохраняется в `~/.kube/config-k3s`.

Использование:

```bash
export KUBECONFIG="$HOME/.kube/config-k3s"
kubectl get nodes
kubectl -n kube-system get pods
```

Пример с явными параметрами:

```bash
bash scripts/pull_kubeconfig.sh \
  --inventory inventories/cloud/hosts.yml \
  --host k3s \
  --user ubuntu \
  --identity ~/.ssh/k3s_deploy \
  --output ~/.kube/config-k3s
```

<a id="step-8"></a>

## Частые ошибки и быстрые фиксы

`the role 'common' was not found`:

- причина: игнорируется `ansible.cfg`, не подхватился `roles_path`;
- фикс: `export ANSIBLE_ROLES_PATH="$(pwd)/roles"`.

`k3s_hosts group missing` в `smoke.yml`:

- причина: отсутствует `inventories/cloud/hosts.yml` или он не заполнен;
- фикс:
  ```bash
  cd deploy/terraform/k3s_deploy
  bash scripts/sync_inventory.sh
  ```

`github_runner_registration_token` missing:

- причина: runner host включен в inventory, но token не задан в
  `group_vars/github_runners/zz-local.yml`;
- фикс: получить fresh registration token в GitHub repo settings и положить
  его в локальный `zz-local.yml`.

`UNREACHABLE` на первом запуске:

- причина: VM еще не готова по SSH после create/reboot;
- фикс: подождать 1-2 минуты и повторить `bootstrap_python.yml`.

`firewall` validation падает на пустых списках CIDR:

- причина: не заполнен `zz-local.yml`;
- фикс: задать реальные CIDR для `firewall_admin_ssh_sources`, `kube_api_allowed_cidrs`, `edge_allowed_client_cidrs`.

`Permission denied (publickey)`:

- причина: не тот ключ;
- фикс:

  ```bash
  # вариант 1: явно передать ключ
  bash scripts/pull_kubeconfig.sh --identity ~/.ssh/k3s_deploy

  # вариант 2: задать ключ через env
  export ANSIBLE_SSH_PRIVATE_KEY_FILE=~/.ssh/k3s_deploy
  bash scripts/pull_kubeconfig.sh
  ```

  Если для этого хоста использовался другой ключ (например `ansible_deploy`),
  передайте его через `--identity`.

`UNREACHABLE` на `github_runners` при прямом SSH:

- причина: runner private-only и не должен быть доступен напрямую;
- фикс: убедиться, что runner расположен в inventory group `private_hosts`,
  а `k3s` доступен по своему публичному `ansible_host`.
