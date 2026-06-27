# Terraform инфраструктура для Этапа B

Terraform инфраструктура для деплоя в Stage B:

- `k3s` — single-node Kubernetes (public subnet, public IP).
- `runner` — optional self-hosted GitHub Actions runner
  (private workload VM for k3s CD).

## Структура

```text
.
├── README.md
├── backend.hcl.example
├── compute.tf
├── locals.tf
├── network.tf
├── outputs.tf
├── providers.tf
├── scripts
│   └── sync_inventory.sh
├── security.tf
├── terraform.tfvars.example
├── variables.tf
└── versions.tf
```

## Backend

В этом стеке используется Terraform backend (S3-compatible YC Object Storage):
state хранится удаленно, а не локально.

Для запуска создается локальный `backend.hcl` из `backend.hcl.example` и
передается в `terraform init -backend-config=backend.hcl`.

## Какие ресурсы создаются

- VPC network,
- 1 subnet для `k3s` и `runner`,
- 1 VM `k3s`,
- optional 1 VM `runner`,
- security group `k3s-single-node-sg`,
- optional security group `k3s-runner-sg`,
- outputs с private/public IP, kube API endpoint и готовым YAML inventory
  для `k3s_hosts` и `github_runners`.

## Сетевой контракт (cloud SG)

`k3s`:

- `22/tcp` от `firewall_admin_ssh_sources`,
- `6443/tcp` от `kube_api_allowed_cidrs` и от private IP runner VM
  (`10.20.0.4/32` в дефолтной схеме, если runner включен),
- `80/tcp` от `edge_http_cidrs` (ACME HTTP-01 + redirect),
- `443/tcp` от `edge_allowed_client_cidrs`.

Egress: `ANY -> 0.0.0.0/0`.

`runner`:

- `22/tcp` от `firewall_admin_ssh_sources`,
- egress `80/tcp` в интернет для `apt update` и Ubuntu package metadata,
- egress `443/tcp` в интернет для GitHub Actions API и download-ов,
- egress `53/tcp` и `53/udp` для DNS,
- egress `6443/tcp` только к private IP `k3s` для `kubectl`/`helmfile`.

`runner` включается только при `runner_enabled = true`. Это separate VM,
которая живет в том же Stage B контуре, но не совмещается с control-plane
нодой `k3s`. По умолчанию runner использует тот же `preemptible` флаг, что и
основная `k3s` VM: модель дешевле по стоимости, но CD-контур становится
best-effort и зависит от доступности runner в момент запуска workflow.

Для доступа runner к Kubernetes API используется отдельное узкое правило:
ingress на `k3s:6443` разрешается не только для внешних admin CIDR, но и для
private IP runner VM. Это intentional least-privilege решение: runner не
получает доступ к API "со всего subnet", а только со своего фиксированного
внутреннего адреса.

## Предусловия

- установлен `terraform >= 1.6`,
- установлен и настроен `yc` CLI (`yc init`),
- есть SSH public key (`~/.ssh/k3s_deploy.pub` по дефолту, если не передать другой),
- у сервисного аккаунта есть права на VPC/VM/SG и на Object Storage backend.

## Создание инфраструктуры

> Секреты и cloud идентификаторы не кладутся в `terraform.tfvars`.
> Передаются только через environment variables.

```bash
cd deploy/terraform/k3s_deploy

# Настройте backend config и tfvars
cp -n backend.hcl.example backend.hcl
cp -n terraform.tfvars.example terraform.tfvars

# При необходимости: заполните terraform.tfvars своими CIDR/IP и runner flags
# (firewall_admin_ssh_sources, kube_api_allowed_cidrs,
#  edge_allowed_client_cidrs, runner_enabled, vm_specs.runner_vm)

# Передайте S3 backend credentials (YC Object Storage)
export AWS_ACCESS_KEY_ID="<access_key_id>"
export AWS_SECRET_ACCESS_KEY="<secret_access_key>"

# Передайте Terraform provider vars
export TF_VAR_yc_token="$(yc iam create-token)"
export TF_VAR_cloud_id="$(yc config get cloud-id)"
export TF_VAR_folder_id="$(yc config get folder-id)"

terraform init -reconfigure -backend-config=backend.hcl
terraform validate
terraform plan -out tfplan
terraform apply tfplan
```

Проверка outputs после `apply`:

```bash
cd deploy/terraform/k3s_deploy

terraform output k3s_private_ip
terraform output k3s_public_ip
terraform output kube_api_endpoint
terraform output runner_private_ip
terraform output runner_public_ip
terraform output -raw ansible_inventory_yaml
```

Генерация inventory для Kubernetes bootstrap:

```bash
cd deploy/terraform/k3s_deploy
bash scripts/sync_inventory.sh
```

После запуска очистите переданные env:

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY \
      TF_VAR_yc_token TF_VAR_cloud_id TF_VAR_folder_id
```

Дальше переходи к bootstrap-этапу:

- [Kubernetes bootstrap (Ansible)](../../kubernetes/bootstrap/README.md)
- [Индекс Этапа B](../../../docs/kubernetes_deploy/README.md)

Runner после bootstrap используется как self-hosted GitHub Actions executor
для `cd-k3s-auto.yml` и `cd-k3s-manual.yml`.

## Удаление инфраструктуры

Чтобы посмотреть, что удалится, и затем удалить инфраструктуру:

```bash
cd deploy/terraform/k3s_deploy

# Передайте S3 backend credentials (YC Object Storage)
export AWS_ACCESS_KEY_ID="<access_key_id>"
export AWS_SECRET_ACCESS_KEY="<secret_access_key>"

# Передайте Terraform provider vars
export TF_VAR_yc_token="$(yc iam create-token)"
export TF_VAR_cloud_id="$(yc config get cloud-id)"
export TF_VAR_folder_id="$(yc config get folder-id)"

terraform init -reconfigure -backend-config=backend.hcl
terraform plan -destroy -out tfdestroy
terraform apply tfdestroy
```

После удаления очистите переданные env:

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY \
      TF_VAR_yc_token TF_VAR_cloud_id TF_VAR_folder_id
```
