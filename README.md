# Internal AI Knowledge Assistant

## Devops/SRE-кейс

Проект показывает не только запуск приложения, а полный инфраструктурный контур вокруг него: cloud-сеть, деплой, TLS, секреты, изоляция сервисов, backup/restore, smoke-проверки, runbook'и и документация.

Реализованы два варианта деплоя одной системы:

| Контур | Модель                         | Основной стек                                                                    |
| ------ | ------------------------------ | -------------------------------------------------------------------------------- |
| Этап A | 4 VM в Yandex Cloud            | Terraform, Ansible, Docker Compose, Nginx, firewalld, Ansible Vault              |
| Этап B | single-node k3s в Yandex Cloud | Terraform, Ansible bootstrap, Kubernetes, Helmfile, Traefik, SOPS, NetworkPolicy |

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
- `4` VM в Этапе A: `wiki`, `db`, `n8n`, `ollama`.
- `1` публичная VM в Этапе A: только `wiki` имеет public IP и выполняет роль edge/bastion.
- `6` Helmfile-слоев в Этапе B: `platform`, `postgres`, `redis`, `wiki`, `ollama`, `n8n`.
- `5` n8n workflow: `agent_query_main`, `memory_read`, `memory_write`, `agent_chat_ui`, `agent_smoke_e2e`.
- `2` собственных Helm-чарта: `n8n` и `ollama`.
- Локально сохраненные сторонние Helm-чарты: `postgresql`, `redis`, `wiki`, `cert-manager`, `raw`.
- Backup/restore PostgreSQL на обоих этапах с проверкой целостности и явным подтверждением восстановления.

## Этап A: VM-контур

Этап A разворачивает сервисы на 4 VM в Yandex Cloud через Terraform, Ansible и Docker Compose.

### Схема

![Схема сети этапа A](./docs/ansible_vm_deploy/diagrams/network-topology.png)

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

![Схема сети этапа B](./docs/kubernetes_deploy/diagrams/network-topology.png)

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
- PostgreSQL, Redis, Wiki.js, cert-manager и raw-ресурсы разворачиваются через локально сохраненные сторонние Helm-чарты.
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
  kubernetes_deploy/     # документация этапа B

n8n/
  workflows/             # workflow ассистента, памяти, UI и smoke
```

## Документация

- [Единая точка входа в документацию](./docs/README.md)
- [Этап A: Terraform + Ansible + Docker Compose](./docs/ansible_vm_deploy/README.md)
- [Этап B: Terraform + Ansible bootstrap + Helmfile](./docs/kubernetes_deploy/README.md)
- [n8n workflows](./n8n/workflows/README.md)

## Дальнейшее развитие

Следующий этап - довести Kubernetes-контур до более production-like платформы.

План развития:

- multi-node Kubernetes вместо single-node k3s;
- отказоустойчивость для PostgreSQL и Redis;
- observability stack: metrics, logs, tracing, alerting;
- CI/CD с проверками Terraform, Ansible, Helm и Kubernetes manifests;
- GitOps-доставка через Argo CD или Flux;
- SRE-практики: SLI/SLO, error budgets, incident playbooks;
- policy/security checks для инфраструктурного кода.
