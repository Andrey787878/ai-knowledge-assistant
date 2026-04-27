# Этап B (k3s): ранбук Ansible bootstrap

Пошаговый ранбук для первого и повторного запуска bootstrap-этапа k3s.
Подготовка single-node k3s VM (OS baseline, firewall, k3s, smoke).

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

<a id="step-2"></a>

## Подготовьте локальные файлы из `.example`

```bash
cd deploy/kubernetes/bootstrap

cp -n inventories/cloud/group_vars/all/zz-local.yml.example inventories/cloud/group_vars/all/zz-local.yml
```

Что заполняем:

- `inventories/cloud/group_vars/all/zz-local.yml`:
  - `firewall_admin_ssh_sources` для `22/tcp`.
  - `kube_api_allowed_cidrs` для `6443/tcp`.
  - `edge_allowed_client_cidrs` для `443/tcp`.
  - при необходимости локально переопределить `k3s_secrets_encryption_enabled` (по умолчанию уже `true` в `group_vars/all/main.yml`).
  - при необходимости локально переопределить `k3s_server_tls_sans`.
  - опционально `edge_http_cidrs` для `80/tcp` (если хотите переопределить).

По умолчанию `edge_http_cidrs` задается в роли firewall как `0.0.0.0/0`
(нужно для HTTP-01 challenge и HTTP->HTTPS redirect).

Файл `zz-local.yml` локальный и не должен коммититься.

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
