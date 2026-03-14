# docker_engine

Роль установки Docker Engine и Docker Compose plugin.

## Что делает

- Проверяет поддерживаемую ОС, дистрибутив и архитектуру.
- Удаляет конфликтующие Docker-пакеты.
- Добавляет официальный Docker-репозиторий и GPG key.
- Устанавливает Docker Engine и Compose plugin.
- Включает и запускает сервис `docker`.
- Управляет `/etc/docker/daemon.json` через переменную `docker_engine_daemon_config`.
- Опционально добавляет пользователя деплоя в группу `docker`.
- Опционально выполняет verify-проверки Docker.

## Предусловия

- Перед `docker_engine` должна быть выполнена роль `base`.

## Граница ответственности

`docker_engine` отвечает только за установку и конфигурацию Docker (engine, service, daemon.json, verify).

## Поддерживаемые платформы

- OS family:
  - `Debian`.
  - `RedHat`.
- Дистрибутивы:
  - `Ubuntu`, `Debian`.
  - `RedHat`, `Rocky`, `AlmaLinux`, `CentOS`, `Fedora`.
- Архитектуры:
  - `x86_64`.
  - `aarch64`.

## Переменные

Значения по умолчанию задаются в `defaults/main.yml`.

- `docker_engine_distribution_map` - маппинг `ansible_distribution` в имя для Docker repo URL.
- `docker_engine_arch_map_debian` - маппинг архитектур для `apt` repo.
- `docker_engine_arch_map_redhat` - маппинг архитектур для `yum/dnf` repo.
- `docker_engine_conflicting_packages_debian` - конфликтующие пакеты для удаления на Debian family.
- `docker_engine_conflicting_packages_redhat` - конфликтующие пакеты для удаления на RedHat family.
- `docker_engine_packages` - пакеты Docker Engine и Compose plugin.
- `docker_engine_manage_user_group` - добавлять пользователя в группу `docker` или нет (по умолчанию `false`).
- `docker_engine_group_user` - пользователь для добавления в группу `docker` (задается явно при `docker_engine_manage_user_group: true`).
- `docker_engine_daemon_config` - словарь конфигурации Docker daemon, рендерится в `/etc/docker/daemon.json`.
- `docker_engine_service_enabled` - включать сервис `docker` в автозапуск или нет (по умолчанию `true`).
- `docker_engine_service_state` - целевое состояние сервиса `docker` (по умолчанию `started`).
- `docker_engine_validate_installation` - включить/выключить verify-задачи.
- `docker_engine_gpg_fingerprint` - ожидаемый fingerprint Docker GPG key.
- `docker_engine_gpg_key_checksum` - опциональный checksum ключа при скачивании.

## Использование

```yaml
- hosts: docker_hosts
  become: true
  roles:
    - docker_engine
```

Если нужно добавить пользователя в группу `docker`, задайте это явно:

```yaml
- hosts: docker_hosts
  become: true
  vars:
    docker_engine_manage_user_group: true
    docker_engine_group_user: ubuntu
  roles:
    - docker_engine
```

Пример настройки daemon:

```yaml
- hosts: docker_hosts
  become: true
  vars:
    docker_engine_daemon_config:
      log-driver: json-file
      log-opts:
        max-size: '10m'
        max-file: '3'
  roles:
    - docker_engine
```

Пример управления сервисом:

```yaml
- hosts: docker_hosts
  become: true
  vars:
    docker_engine_service_enabled: true
    docker_engine_service_state: started
  roles:
    - docker_engine
```

## Поведение

Роль работает по принципу `fail-fast` и завершится ошибкой на неподдерживаемой платформе или невалидных параметрах.

Повторный запуск не должен ничего менять на хосте без необходимости.

Verify-задачи выполняются только при `docker_engine_validate_installation: true`.

При непустом `docker_engine_daemon_config` роль рендерит `/etc/docker/daemon.json`. При пустом — удаляет файл. Любое изменение файла вызывает перезапуск Docker через handler.
Проверка `docker info` выполняется только когда целевое состояние сервиса предполагает работающий daemon (`started`, `restarted`, `reloaded`).

## После деплоя

Если включен `docker_engine_manage_user_group: true`, роль добавляет явно заданного пользователя в группу `docker`, но новые права применяются только в новой сессии.

Чтобы права применились:

1. Завершите текущую SSH-сессию.
2. Подключитесь к хосту заново.
3. Проверьте:
   - `id -nG` (в списке должна быть группа `docker`).
   - `docker ps` (должно работать без `sudo`).

## Быстрая проверка

```bash
docker --version
docker compose version
docker info --format '{{.ServerVersion}}'
systemctl is-enabled docker
systemctl is-active docker
```

Автопроверки в роли выполняются только при `docker_engine_validate_installation: true`.
