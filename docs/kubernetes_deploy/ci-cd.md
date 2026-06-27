# CI/CD для этапов B и C

Этот документ описывает delivery-контур для Kubernetes-этапа: как устроены
`CI`, `CD`, self-hosted runner, partial deploy по scope и post-deploy smoke
checks.

## Назначение

Этап B вручную поднимает `k3s`-контур и прикладные Helmfile-слои. Этап C добавляет
поверх него pipeline-практики: автоматическую проверку инфраструктурного кода,
деплой из GitHub Actions и операционный контракт для выката в production.

Контур разделен на две части:

- `CI` валидирует репозиторий и не трогает кластер;
- `CD` выполняется внутри инфраструктурного периметра через отдельную VM
  `runner`, у которой есть доступ к `k3s` API и ключам для расшифровки secret
  values.

## Delivery model

Текущая модель простая и предсказуемая. Источником истины остается репозиторий,
а применение изменений в кластер идет только через GitHub Actions на
self-hosted runner.

Ожидаемый operational contract:

- рабочие изменения вносятся через feature-ветки и Pull Request;
- ветка `main` используется как production source of truth;
- auto deploy запускается после merge или прямого push в `main`;
- ручной deploy используется для full re-apply, точечного scope deploy и
  controlled rerun.

Если branch protection для `main` еще не включен в настройках GitHub, этот
документ предполагает именно такую целевую модель.

## Что входит в CI

Основной workflow:

- `.github/workflows/ci.yml`

CI не зависит от кластера и служит входным quality gate перед merge.

Сейчас в CI уже проверяются:

- YAML и workflow-файлы;
- `n8n` workflow JSON;
- `gitleaks` secret scan;
- `terraform fmt`, `terraform validate`, `tflint`;
- Helm/Helmfile template-валидация;
- `bash -n` и `shellcheck` для служебных скриптов;
- Ansible syntax-check.

Этот слой нужен не для демонстрации ради галочки, а чтобы ловить типовые
ошибки до того, как они попадут в production deploy path.

## Что входит в CD

Production deploy построен вокруг двух workflow:

- `.github/workflows/cd-k3s-auto.yml`
- `.github/workflows/cd-k3s-manual.yml`

Оба workflow запускаются не на GitHub-hosted runner, а на отдельной VM
`runner`, которая создается Terraform-стеком `deploy/terraform/k3s_deploy` и
bootstrap-ится ролью `github_runner`.

Runner зарегистрирован с labels:

- `self-hosted`
- `linux`
- `x64`
- `k3s`
- `prod`
- `deploy`
- `stage-b`

`runs-on` у deploy workflow завязан именно на этот label-set. Это защищает
контур от случайного запуска на неподготовленном хосте без `kubectl`,
`helmfile`, `sops` и `kubeconfig`.

## Почему self-hosted runner вынесен в отдельную VM

Runner не совмещается с control-plane нодой `k3s`. Это отдельная VM в том же
cloud perimeter.

Такое разделение дает три практических эффекта:

- CD не конкурирует с control-plane и workload-подами за CPU и память;
- GitHub runner lifecycle не смешивается с lifecycle кластера;
- права, firewall и operational troubleshooting у deploy-host остаются
  отдельными от `k3s`-ноды.

С точки зрения операционной модели runner - это внутренний deploy bastion для
Stage B/C.

В текущей конфигурации runner использует тот же `preemptible` режим, что и
основная `k3s` VM. Это снижает стоимость, но делает CD-контур best-effort:
если VM была прервана облаком, workflow не сможет стартовать, пока runner не
вернется в строй и не зарегистрируется снова как рабочий хост.

## Runner contract

Runner host готовится ролью:

- `deploy/kubernetes/bootstrap/roles/github_runner`

Во время bootstrap на runner настраиваются:

- GitHub Actions runner как systemd service;
- `kubectl`, `helm`, `helmfile`, `sops`, `age`, `helm-secrets`;
- `KUBECONFIG=/home/github-runner/.kube/config`;
- `SOPS_AGE_KEY_FILE=/home/github-runner/.config/sops/age/keys.txt`;
- доступ к `k3s` API по private endpoint;
- локальный material для расшифровки SOPS-encrypted secret values.

Сетевой доступ runner к `k3s` API специально зажат с двух сторон:

- на runner разрешён egress `6443/tcp` только к private IP `k3s`;
- на `k3s` разрешён ingress `6443/tcp` не только от внешних admin CIDR, но и
  от private IP runner VM.

Это intentional least-privilege схема для CD-контура: deploy-host может
достучаться до Kubernetes API, но не получает лишнего сетевого доступа внутри
subnet.

Секретная модель у runner двусоставная:

- short-lived GitHub registration token для первичной регистрации runner;
- `age` private key для `sops`/`helm-secrets`, чтобы workflow могли применять
  encrypted Helm values.

Оба секрета не хранятся в репозитории и должны попадать только в локальные
`zz-local.yml` файлы bootstrap inventory.

Откуда берутся значения:

- `github_runner_registration_token`:
  `Settings -> Actions -> Runners -> New self-hosted runner`
- `github_runner_sops_age_key`:
  существующий локальный `~/.config/sops/age/keys.txt`, который уже
  расшифровывает проектные `*.enc.yaml`

## Auto deploy flow

Workflow:

- `.github/workflows/cd-k3s-auto.yml`

Trigger:

- `push` в `main`

Логика auto deploy:

1. workflow checkout-ит репозиторий с полной историей;
2. script `detect-k3s-scopes.sh` вычисляет, какие Kubernetes-слои реально
   изменились;
3. если изменения не затрагивают `deploy/kubernetes`, deploy gracefully
   пропускается;
4. для каждого вычисленного scope выполняются:
   - `deploy-k3s-scope.sh`
   - `smoke-k3s-scope.sh`
5. итог пишется в `GITHUB_STEP_SUMMARY`.

Главная идея здесь в том, что обычное изменение, например, только в
`deploy/kubernetes/apps/wiki`, не должно каждый раз прогонять полный re-apply
всего кластера.

## Manual deploy flow

Workflow:

- `.github/workflows/cd-k3s-manual.yml`

Trigger:

- `workflow_dispatch`

Manual deploy поддерживает три режима:

- `full` — полное применение root Helmfile;
- `scope` — точечный deploy одного слоя;
- `changed` — deploy только измененных scope для выбранного `ref`.

Дополнительно ручной workflow требует явного подтверждения через input
`confirm_prod=DEPLOY`. Это простой, но полезный предохранитель от случайного
ручного выката в production.

`changed` mode стоит воспринимать как convenience-режим, а не как самый
строгий operational path. Он полезен, когда diff хорошо понятен и нужно быстро
переиграть частичный deploy без полного re-apply. Для максимально
предсказуемого production-сценария предпочтительнее `scope` или `full`, потому
что они не зависят от того, как именно вычислился набор измененных слоев.

## Scope model

CD работает не по сервисам в общем смысле, а по конкретным Helmfile-слоям.

Поддерживаемые scope:

- `platform`
- `observability`
- `postgres`
- `redis`
- `wiki`
- `ollama`
- `n8n`
- `all`

Соответствие файлов и scope задается в:

- `.github/scripts/cd/detect-k3s-scopes.sh`

Текущая логика такая:

- изменение `deploy/kubernetes/helmfile.yaml` ведет к `all`;
- изменение внутри конкретного layer path ведет только к соответствующему
  scope;
- изменения только в `docs` или верхнеуровневом `README` не запускают deploy.

Это делает CD дешевле по времени и понятнее по blast radius.

Для `workflow_dispatch` в режиме `changed` действует тот же принцип: workflow
пытается вычислить измененные scope из git diff для выбранного `ref`, но этот
режим лучше использовать как операторское удобство, а не как единственный
строгий механизм выпуска.

## Deploy scripts

Весь runtime-контур CD вынесен в явные bash-скрипты:

- `.github/scripts/cd/detect-k3s-scopes.sh`
- `.github/scripts/cd/deploy-k3s-scope.sh`
- `.github/scripts/cd/smoke-k3s-scope.sh`

Такой подход выбран сознательно. Сложная логика остается не в YAML workflow, а
в обычных скриптах, которые можно:

- читать отдельно от GitHub UI;
- lint-ить через `shellcheck`;
- проверять через `bash -n`;
- переиспользовать локально при troubleshooting.

## Post-deploy smoke checks

Каждый scope после `helmfile sync` проходит свой smoke path.

Примеры:

- `platform` проверяет namespaces, `cert-manager` и `ClusterIssuer`;
- `observability` проверяет `Prometheus`, `Alertmanager`, `Grafana`, `Loki`,
  `Alloy` и наличие `ServiceMonitor`/`PrometheusRule`/`Probe`;
- `postgres` проверяет StatefulSet, service и backup CronJob;
- `wiki` и `n8n` делают не только rollout status, но и HTTP health checks через
  `kubectl port-forward`;
- `ollama` проверяет `/api/version`.

Это не заменяет полноценный e2e acceptance, но хорошо закрывает operational
уровень "релиз применился и базовый контракт сервиса жив".

## Concurrency и production safety

Оба CD workflow используют общий concurrency group:

- `k3s-prod-deploy`

`cancel-in-progress: false` выбран специально. Если один production deploy уже
идет, следующий не должен его обрывать посередине. Он должен дождаться своей
очереди.

Дополнительные защитные рамки:

- у workflow есть `environment: production`;
- manual deploy требует `confirm_prod=DEPLOY`;
- runner labels ограничивают место выполнения;
- deploy идет только через runner с private доступом к кластеру.

## Что считается успешным deploy

Для этого контура успешный deploy означает не просто зеленый GitHub job.

Успехом считаются одновременно три условия:

- `helmfile sync` для нужного scope завершился без ошибок;
- scope-specific smoke checks завершились без ошибок;
- workflow записал осмысленный summary с примененным scope и `ref`.

Если deploy job зеленый, но smoke path упал, релиз считается неуспешным.

## Failure model

Сейчас контур рассчитан на простую и понятную operational модель.

Если deploy падает:

- GitHub Actions сохраняет лог deploy step;
- scope известен явно;
- команда может перезапустить либо тот же scope, либо full deploy из manual
  workflow;
- troubleshooting делается на runner и в кластере стандартными `kubectl`,
  `helmfile` и observability-инструментами.

Rollback как отдельная автоматика в этот документ не входит. Текущая модель
делает ставку на deterministic re-apply, scope isolation и smoke checks после
каждого применения.

## Что стоит показать на скриншотах

В этот документ удобно потом вставить:

- скриншот списка GitHub Actions workflow с `ci`, `cd-k3s-auto`,
  `cd-k3s-manual`;
- скриншот успешного `cd-k3s-auto` run с summary по scope;
- скриншот manual workflow dispatch с режимами `full`, `scope`, `changed`;
- скриншот self-hosted runner labels в GitHub UI;
- при желании скриншот environment `production` и branch protection для `main`.

Можно оставить эти скриншоты в README уровня этапа B/C, а этот документ держать
как текстовый runbook.

## Связанная документация

- [Индекс этапов B+C](./README.md)
- [Terraform инфраструктура Stage B](../../deploy/terraform/k3s_deploy/README.md)
- [Bootstrap k3s и runner](../../deploy/kubernetes/bootstrap/README.md)
- [Kubernetes runbook](../../deploy/kubernetes/README.md)
- [Monitoring и alerting](./monitoring.md)
