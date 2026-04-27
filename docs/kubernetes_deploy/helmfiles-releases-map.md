# Карта этапа B: bootstrap, Helmfile и releases

## Область

Документ показывает, кто за что отвечает на этапе B:

- Terraform слой инфраструктуры,
- Ansible bootstrap k3s,
- Helmfile platform/apps,
- release-файлы и значения (`values`/`secrets`).

## Общая архитектура запуска

Порядок этапа B:

1. Terraform: `deploy/terraform/k3s_deploy`
2. Bootstrap: `deploy/kubernetes/bootstrap` (Ansible)
3. Kubernetes platform: `deploy/kubernetes/platform`
4. Kubernetes apps: `deploy/kubernetes/apps/*`

Главный вход Helmfile:

- [deploy/kubernetes/helmfile.yaml](../../deploy/kubernetes/helmfile.yaml)

## Bootstrap (Ansible)

Playbook:

- [deploy/kubernetes/bootstrap/playbooks/site.yml](../../deploy/kubernetes/bootstrap/playbooks/site.yml)

Роли:

1. `common` — базовая подготовка VM
2. `firewall` — host firewall правила (22/6443/80/443)
3. `k3s_server` — установка/настройка k3s single-node

Ключевые переменные bootstrap:

- `deploy/kubernetes/bootstrap/inventories/cloud/group_vars/all/main.yml`
- `deploy/kubernetes/bootstrap/inventories/cloud/group_vars/all/zz-local.yml`

## Helmfile: верхний уровень

В [deploy/kubernetes/helmfile.yaml](../../deploy/kubernetes/helmfile.yaml) слои идут строго по порядку:

1. `platform/helmfile.yaml`
2. `apps/postgres/helmfile.yaml`
3. `apps/redis/helmfile.yaml`
4. `apps/wiki/helmfile.yaml`
5. `apps/ollama/helmfile.yaml`
6. `apps/n8n/helmfile.yaml`

## Platform слой

Helmfile:

- [deploy/kubernetes/platform/helmfile.yaml](../../deploy/kubernetes/platform/helmfile.yaml)

Releases:

- `releases/cert-manager.yaml` — установка cert-manager
- `releases/cluster-issuer.yaml` — ClusterIssuer letsencrypt-prod

Values:

- `environments/prod/platform.values.yaml`
- `environments/prod/cluster-issuer.values.yaml`

## Apps слой (карта по namespace)

### `db` namespace (PostgreSQL)

Helmfile:

- [deploy/kubernetes/apps/postgres/helmfile.yaml](../../deploy/kubernetes/apps/postgres/helmfile.yaml)

Releases:

- `initdb-secret.yaml` — init SQL/секреты инициализации
- `postgres.yaml` — основной PostgreSQL release
- `networkpolicy.yaml` — сетевые правила `db`
- `backup-cronjob.yaml` — регулярный backup
- `restore-job.yaml` — one-shot restore (через restore helmfile)

Values:

- `environments/prod/meta.values.yaml`
- `environments/prod/app.values.yaml`
- `environments/prod/backup.values.yaml`
- `environments/prod/restore.values.yaml`
- `environments/prod/secrets.values.enc.yaml`

### `n8n` namespace (n8n + Redis)

Helmfile:

- [deploy/kubernetes/apps/n8n/helmfile.yaml](../../deploy/kubernetes/apps/n8n/helmfile.yaml)

Releases:

- `networkpolicy.yaml` — сетевые правила `n8n`
- `http-redirect-middleware.yaml` — middleware HTTP->HTTPS
- `n8n.yaml` — web/worker deployment + service + ingress
- `workflows.yaml` — import/reconcile workflows и credentials

Values:

- `environments/prod/meta.values.yaml`
- `environments/prod/app.values.yaml`
- `environments/prod/workflows.values.yaml`
- `environments/prod/secrets.values.enc.yaml`

### `n8n` namespace (Redis release)

Helmfile:

- [deploy/kubernetes/apps/redis/helmfile.yaml](../../deploy/kubernetes/apps/redis/helmfile.yaml)

Releases:

- `auth-secret.yaml` — redis auth secret
- `networkpolicy.yaml` — сетевые правила Redis
- `redis.yaml` — redis statefulset/service

Values:

- `environments/prod/meta.values.yaml`
- `environments/prod/app.values.yaml`
- `environments/prod/secrets.values.enc.yaml`

### `wiki` namespace (Wiki.js)

Helmfile:

- [deploy/kubernetes/apps/wiki/helmfile.yaml](../../deploy/kubernetes/apps/wiki/helmfile.yaml)

Releases:

- `networkpolicy.yaml` — сетевые правила `wiki`
- `http-redirect-middleware.yaml` — middleware HTTP->HTTPS
- `db-secret.yaml` — external DB secret для Wiki.js
- `wikijs.yaml` — Wiki.js release (service/ingress)

Values:

- `environments/prod/meta.values.yaml`
- `environments/prod/app.values.yaml`

### `ollama` namespace (LLM runtime)

Helmfile:

- [deploy/kubernetes/apps/ollama/helmfile.yaml](../../deploy/kubernetes/apps/ollama/helmfile.yaml)

Releases:

- `networkpolicy.yaml` — сетевые правила `ollama`
- `ollama.yaml` — ollama deployment/service
- `model-pull-job.yaml` — загрузка модели в runtime

Values:

- `environments/prod/meta.values.yaml`
- `environments/prod/app.values.yaml`
- `environments/prod/model.values.yaml`

## Операционный цикл (единый шаблон)

Для любого слоя:

1. `helmfile -e prod build`
2. `helmfile -e prod sync`
3. rollout/health проверки через `kubectl`

Полный прогон:

```bash
cd deploy/kubernetes
helmfile -e prod build > /tmp/k8s-stage-build.yaml
helmfile -e prod sync
```

## Связанные документы

- [README этапа B](./README.md)
- [Сеть этапа B](./network.md)
- [Эксплуатация этапа B](./operations-stage-b.md)
