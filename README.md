[![CI](https://github.com/Andrey787878/ai-knowledge-assistant/actions/workflows/ci.yml/badge.svg)](https://github.com/Andrey787878/ai-knowledge-assistant/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/Andrey787878/ai-knowledge-assistant?style=flat-square)](./LICENSE)
[![Docs](https://img.shields.io/badge/docs-entry_point-1f6feb?style=flat-square)](./docs/README.md)
[![Stage_A](https://img.shields.io/badge/stage-A_4_VM-2ea043?style=flat-square)](./docs/ansible_vm_deploy/README.md)
[![Stage_B_C](https://img.shields.io/badge/stage-B%2BC_k3s_CI/CD_observability-7c3aed?style=flat-square)](./docs/kubernetes_deploy/README.md)

# Internal AI Knowledge Assistant

**Быстрые ссылки:** [Документация](./docs/README.md) • [Этап A](./docs/ansible_vm_deploy/README.md) • [Этапы B + C](./docs/kubernetes_deploy/README.md)

## Devops/SRE-кейс

Проект демонстрирует не только запуск приложения, а полный инфраструктурный контур вокруг него: cloud-сеть, деплой, TLS, секреты, изоляция сервисов, backup/restore, smoke-проверки, runbook'и и документация.

Реализованы два инфраструктурных контура и отдельный Этап C, который добавляет к Этапу B CI/CD и observability:

| Контур | Модель                            | Основной стек                                                                                                  |
| ------ | --------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| Этап A | 4 VM в Yandex Cloud               | Terraform, Ansible, Docker Compose, Nginx, firewalld, Ansible Vault                                            |
| Этап B | single-node k3s в Yandex Cloud    | Terraform, Ansible bootstrap, Kubernetes, Helmfile, Traefik, SOPS, NetworkPolicy                               |
| Этап C | CI и observability поверх Этапа B | GitHub Actions CI, kube-prometheus-stack, Alertmanager, Grafana, Loki, Alloy, blackbox probes, SLI/SLO, alerts |

## Зачем этот проект

В командах часто возникает ситуация, когда знания об инфраструктуре и внутренних процессах распределены по разным источникам.

Из-за этого:

- важные знания теряются при отпуске или уходе сотрудников,
- новым сотрудникам сложнее погрузиться в работу,
- одни и те же вопросы повторяются,
- время, затраченное на решение инцидентов, увеличивается.

Цель проекта - создать единую централизованную систему знаний, которая использует Wiki как базу знаний и предоставляет быстрые, структурированные ответы на вопросы об инфраструктуре.

## Как работает система

Wiki.js выступает единым централизованным источником знаний, PostgreSQL хранит данные Wiki.js, состояние n8n и память диалогов, Redis используется как broker для queue mode, n8n разделен на web и worker и выполняет роль оркестратора, а Ollama запускает локальную LLM. Пользователь задает вопрос, n8n обрабатывает workflow: достает релевантный контекст из базы Wiki.js, формирует промпт, отправляет запрос в Ollama и применяет guard-логику. Если подходящего контекста нет, ассистент не выдумывает ответ, а возвращает "Нет данных".

Основные компоненты:

| Компонент  | Роль                                                                      |
| ---------- | ------------------------------------------------------------------------- |
| Wiki.js    | хранит страницы базы знаний                                               |
| n8n-web    | принимает запросы через UI/API/webhook                                    |
| n8n-worker | выполняет workflow в queue mode                                           |
| Redis      | брокер очереди для n8n queue mode                                         |
| PostgreSQL | хранит данные Wiki.js, n8n и память диалогов агента                       |
| Ollama     | запускает локальную LLM без передачи внутреннего контекста во внешние API |

Пайплайн ответа:

```text
Пользователь
  -> n8n webhook agent-query
  -> запись вопроса в память диалога
  -> поиск релевантного контекста в PostgreSQL базе Wiki.js
  -> формирование prompt для локальной LLM
  -> запрос в Ollama
  -> проверка ответа guard-логикой
  -> запись ответа в память, если он валиден
  -> JSON-ответ пользователю
```

Если релевантный контекст не найден или ответ не проходит проверку, ассистент возвращает `Нет данных.`.

## Что реализовано

- `2` воспроизводимых контура деплоя: VM-контур и Kubernetes-контур.
- `1` Этап C, который добавляет к Этапу B CI и observability.
- `4` VM в Этапе A: `wiki`, `db`, `n8n`, `ollama`.
- `1` публичная VM в Этапе A: только `wiki` имеет public IP и выполняет роль edge/bastion.
- `7` Helmfile-слоев в Этапе B: `platform`, `observability`, `postgres`, `redis`, `wiki`, `ollama`, `n8n`.
- `1` GitHub Actions CI workflow с `5` независимыми job: repository sanity, secret scan, Terraform, Helm, Ansible syntax.
- `5` n8n workflow: `agent_query_main`, `memory_read`, `memory_write`, `agent_chat_ui`, `agent_smoke_e2e`.
- `2` собственных Helm-чарта: `n8n` и `ollama`.
- `3` provisioned Grafana dashboard в observability-слое: `Observability Overview`, `n8n Runtime`, `Public Endpoints / Edge`.
- `6` групп alerting-правил: internal availability, public endpoints, dependencies, `n8n` runtime, self-monitoring, ingress HTTP.
- `2` публичных synthetic HTTPS probe и `3` внутренних blackbox probe для `n8n`, `wiki`, `ollama`.
- Локально сохраненные сторонние Helm-чарты: `postgresql`, `redis`, `wiki`, `cert-manager`, `kube-prometheus-stack`, `loki`, `alloy`, `raw`.
- Backup/restore PostgreSQL на обоих этапах с проверкой целостности и явным подтверждением восстановления.

## Этап A: VM-контур

Этап A разворачивает сервисы на 4 VM в Yandex Cloud через Terraform, Ansible и Docker Compose.

### Схема

<p align="center">
  <a href="./docs/ansible_vm_deploy/diagrams/network-topology.png">
    <img src="./docs/ansible_vm_deploy/diagrams/network-topology.png" alt="Схема сети этапа A" width="920">
  </a>
</p>

<p align="center">
  <a href="./docs/ansible_vm_deploy/diagrams/network-topology.png">
    <img src="https://img.shields.io/badge/Open-full_size-1f6feb?style=for-the-badge" alt="Open full size">
  </a>
  <a href="./docs/ansible_vm_deploy/README.md">
    <img src="https://img.shields.io/badge/Docs-stage_A-2ea043?style=for-the-badge" alt="Stage A docs">
  </a>
</p>

Что сделано:

- Terraform создает VPC, public/private subnet, NAT egress, Security Groups и VM.
- В public subnet находится только `wiki` VM с public IP.
- `db`, `n8n`, `ollama` находятся в private subnet без public IP.
- Доступ к private VM идет через bastion/SSH ProxyJump.
- Ansible настраивает хосты, Docker, firewall, сервисы и smoke-проверки.
- Nginx на edge VM выполняет reverse proxy для Wiki.js и n8n.
- TLS выпускается через Let's Encrypt ACME HTTP-01.
- PostgreSQL дополнительно ограничен через `pg_hba.conf`.
- Секреты хранятся в Ansible Vault.
- Backup/restore PostgreSQL вынесен в отдельные Ansible playbook'и и роль.

Ключевые директории:

| Область      | Путь                              |
| ------------ | --------------------------------- |
| Terraform    | `deploy/terraform/ansible_deploy` |
| Ansible      | `deploy/ansible`                  |
| Документация | `docs/ansible_vm_deploy`          |

## Этап B: Kubernetes-контур

Этап B переносит систему в single-node k3s в Yandex Cloud.

### Схема

<p align="center">
  <a href="./docs/kubernetes_deploy/diagrams/network-topology.png">
    <img src="./docs/kubernetes_deploy/diagrams/network-topology.png" alt="Схема сети этапа B" width="920">
  </a>
</p>

<p align="center">
  <a href="./docs/kubernetes_deploy/diagrams/network-topology.png">
    <img src="https://img.shields.io/badge/Open-full_size-1f6feb?style=for-the-badge" alt="Open full size">
  </a>
  <a href="./docs/kubernetes_deploy/README.md">
    <img src="https://img.shields.io/badge/Docs-stage_B%2BC-7c3aed?style=for-the-badge" alt="Stage B/C docs">
  </a>
</p>

Что сделано:

- Terraform создает cloud-инфраструктуру для k3s-ноды.
- Ansible bootstrap устанавливает k3s с фиксированной версией и checksum-проверкой бинарника.
- k3s настраивается с TLS SAN и шифрованием Kubernetes Secrets at rest.
- Корневой Helmfile собирает platform-слой и app-слои.
- Используется встроенный в k3s Traefik ingress controller.
- cert-manager и ClusterIssuer выпускают TLS-сертификаты через ACME HTTP-01.
- HTTP-to-HTTPS redirect настроен через Traefik Middleware.
- Kubernetes secrets хранятся в SOPS-encrypted values.
- Для n8n и Ollama написаны собственные Helm-чарты.
- PostgreSQL, Redis, Wiki.js, cert-manager, observability-компоненты и raw-ресурсы разворачиваются через локально сохраненные сторонние Helm-чарты.
- NetworkPolicy реализует запрет по умолчанию и точечные разрешения только для нужных сервисных связей.

Ключевые директории:

| Область       | Путь                              |
| ------------- | --------------------------------- |
| Terraform     | `deploy/terraform/k3s_deploy`     |
| k3s bootstrap | `deploy/kubernetes/bootstrap`     |
| Helmfile root | `deploy/kubernetes/helmfile.yaml` |
| Platform      | `deploy/kubernetes/platform`      |
| Applications  | `deploy/kubernetes/apps`          |
| Документация  | `docs/kubernetes_deploy`          |

## Этап C: CI и observability поверх Этапа B

Этап C не создает новый инфраструктурный контур и не дублирует Этап B. Он развивает уже собранный Kubernetes-контур в двух направлениях: добавляет CI-проверки для инфраструктурного кода и добавляет рабочий observability-слой для эксплуатации кластера и приложений.

Что добавлено в Этапе C:

- GitHub Actions CI для YAML, workflow JSON, secret scan, Terraform, Helm/Helmfile/kubeconform и Ansible syntax-check;
- `kube-prometheus-stack` с Prometheus, Alertmanager и Grafana;
- `Loki` и `Alloy` для централизованного сбора pod logs;
- blackbox probes для внутренней и публичной доступности;
- Traefik ingress metrics для user-facing HTTP golden signals;
- recording rules, alert rules и routing в Alertmanager;
- `3` provisioned dashboard, которые приезжают из репозитория без ручного импорта;
- operational документация по SLI/SLO, alerting и post-rollout проверкам.

Ключевые директории:

| Область        | Путь                                       |
| -------------- | ------------------------------------------ |
| CI             | `.github/workflows/ci.yml`                 |
| Helmfile layer | `deploy/kubernetes/observability`          |
| Alerting/SLI   | `deploy/kubernetes/observability/releases` |
| Документация   | `docs/kubernetes_deploy`                   |

## Сеть и безопасность

Проектная модель строится вокруг минимальной публичной поверхности и явных сервисных потоков.

Общие принципы:

- внешний вход только через edge/ingress;
- SSH и web-доступ ограничиваются allow-list CIDR;
- внутренние сервисы не публикуются напрямую в интернет;
- доступы дублируются на нескольких уровнях: cloud perimeter, host firewall, application/cluster policy;
- TLS обязателен для внешнего пользовательского трафика;
- секреты не хранятся в открытом виде в репозитории.

Этап A:

| Уровень         | Реализация                                           |
| --------------- | ---------------------------------------------------- |
| Cloud perimeter | Yandex Cloud Security Groups                         |
| Сегментация     | public/private subnet, public IP только у `wiki` VM  |
| Админ-доступ    | SSH через bastion/ProxyJump                          |
| Host firewall   | firewalld, source-based rich rules, strict reconcile |
| Edge            | Nginx reverse proxy, allow-list, TLS/ACME HTTP-01    |
| Database access | PostgreSQL `pg_hba.conf` с явными источниками        |
| Egress          | private VM выходят наружу через NAT                  |

Этап B:

| Уровень         | Реализация                                                     |
| --------------- | -------------------------------------------------------------- |
| Cloud perimeter | Yandex Cloud Security Group для k3s VM                         |
| Host firewall   | UFW, deny incoming, allow только нужных портов/CIDR            |
| Edge            | встроенный Traefik ingress controller                          |
| TLS             | cert-manager + ClusterIssuer + ACME HTTP-01                    |
| Secrets         | SOPS values и k3s secrets encryption at rest                   |
| Pod network     | NetworkPolicy с запретом по умолчанию и точечными разрешениями |
| Egress          | DNS для нужных pod'ов, Internet 443 только где требуется       |

## Эксплуатация и восстановление

Что реализовано:

- smoke-проверки после деплоя;
- минимальный e2e workflow для проверки агентского сценария;
- импорт n8n workflows без ручной настройки через UI;
- PostgreSQL backup/restore в VM-контуре через Ansible;
- PostgreSQL backup CronJob и one-shot restore Job в Kubernetes-контуре;
- проверка целостности backup перед restore;
- явное подтверждение restore;
- runbook'и по сети, сертификатам, backup/restore и операциям;
- архитектурные схемы для обоих этапов.

Дополнительно в observability-слое реализованы:

- `3` dashboard для overview, runtime и public edge-path;
- SLI/SLO слой для internal availability, public availability, ingress latency/error rate и dependency health;
- Alertmanager routing, в котором actionable alerting отделен от SLO-history warning-сигналов;
- self-monitoring для Prometheus scrape health и доставки уведомлений.

Отдельно в CI уже реализованы:

- `yamllint` для `.github` и `deploy`;
- валидация `n8n` workflow JSON;
- `gitleaks` secret scan;
- `terraform fmt`, `terraform validate`, `tflint`;
- `helm lint`, `helm template`, `helmfile build/template`, `kubeconform`;
- `shellcheck`, `bash -n` и `ansible-playbook --syntax-check` для VM и k3s bootstrap playbook'ов.

## Структура репозитория

```text
deploy/
  terraform/
    ansible_deploy/      # Terraform для 4 VM контура
    k3s_deploy/          # Terraform для k3s контура
  ansible/               # Ansible роли и playbook'и этапа A
  kubernetes/
    bootstrap/           # Ansible bootstrap для k3s
    platform/            # namespaces, cert-manager, ClusterIssuer
    apps/                # postgres, redis, wiki, ollama, n8n
    vendor_charts/       # локально сохраненные сторонние Helm-чарты

docs/
  ansible_vm_deploy/     # документация этапа A
  kubernetes_deploy/     # документация этапов B и C

n8n/
  workflows/             # workflow ассистента, памяти, UI и smoke
```

## Документация

- [Единая точка входа в документацию](./docs/README.md)
- [Этап A: Terraform + Ansible + Docker Compose](./docs/ansible_vm_deploy/README.md)
- [Этапы B/C: Terraform + k3s bootstrap + Helmfile + CI/observability](./docs/kubernetes_deploy/README.md)
- [n8n workflows](./n8n/workflows/README.md)
