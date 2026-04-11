# Terraform инфраструктура для Этапа A

Terraform инфраструктура для деплоя в 4 VM:

- `wiki` — edge reverse proxy + bastion (public subnet, public IP),
- `postgres`, `ollama`, `n8n` — private VM (private subnet, без public IP).

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
- 2 subnet:
  - `public` для `wiki`,
  - `private` для `db/ollama/n8n`,
- NAT Gateway + route table (`0.0.0.0/0`) для private subnet,
- 4 VM,
- 2 security groups:
  - `ansible-bastion-sg` (для `wiki`),
  - `ansible-private-sg` (для `db/ollama/n8n`),
- outputs с private/public IP и готовым YAML inventory для Ansible.

## Сетевой контракт (cloud SG)

`wiki`:

- `22/tcp` от `firewall_admin_ssh_sources`,
- `80/tcp` от `edge_http_cidrs` (ACME HTTP-01 + redirect),
- `443/tcp` от `edge_allowed_client_cidrs`.

`db/ollama/n8n`:

- `22/tcp` только от `wiki.private_ip/32`,
- `5432/tcp` от `n8n.private_ip/32` и `wiki.private_ip/32`,
- `5678/tcp` от `wiki.private_ip/32`,
- `11434/tcp` от `n8n.private_ip/32`.

Egress для обоих SG: `ANY -> 0.0.0.0/0`.

## Предусловия

- установлен `terraform >= 1.6`,
- установлен и настроен `yc` CLI (`yc init`),
- есть SSH public key (`~/.ssh/ansible_deploy.pub` по дефолту, если не передать другой),
- у сервисного аккаунта есть права на VPC/VM/SG и на Object Storage backend.

## Создание инфраструктуры

> Секреты и cloud идентификаторы не кладутся в `terraform.tfvars`.
> Передаются только через environment variables.

```bash
cd deploy/terraform/ansible_deploy

# Настройте backend config и tfvars
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars

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

После запуска очистите переданные env:

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY \
      TF_VAR_yc_token TF_VAR_cloud_id TF_VAR_folder_id
```

## Генерация inventory для Ansible

```bash
cd deploy/terraform/ansible_deploy
bash scripts/sync_inventory.sh
```

Дальше переходи к Ansible-этапу:

- [Ansible runbook (первый/повторный прогон)](../../ansible/README.md)
- [Карта ролей и playbook'ов](../../../docs/ansible_vm_deploy/roles-playbooks-map.md)

## Удаление инфраструктуры

Чтобы посмотреть, что удалится, и затем удалить инфраструктуру:

```bash
cd deploy/terraform/ansible_deploy

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
