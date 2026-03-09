# docker_engine

Роль установки Docker Engine и Docker Compose plugin на Debian/Ubuntu хостах.

## Что делает

- Проверяет поддерживаемую ОС.
- Проверяет корректность параметров Docker репозитория.
- Добавляет официальный Docker apt-репозиторий и GPG key.
- Устанавливает Docker пакеты.
- Включает и запускает сервис `docker`.
- Опционально добавляет пользователя деплоя в группу `docker`.
- Опционально проверяет `docker --version`, `docker compose version` и состояние сервиса Docker.

## Что роль не делает

- Не деплоит прикладные контейнеры и compose-стеки.
- Не управляет конфигурацией конкретных сервисов.

## Поддерживаемые платформы

- Дистрибутивы: `Debian`, `Ubuntu`.
- Архитектуры: `x86_64`, `aarch64`.

## Переменные

Значения по умолчанию задаются в `defaults/main.yml`.

- `docker_engine_supported_os_families` — поддерживаемые семейства ОС.
- `docker_engine_prerequisite_packages` — пакеты-предпосылки для репозитория Docker.
- `docker_engine_packages` — пакеты Docker Engine и Compose plugin.
- `docker_engine_manage_user_group` — добавлять пользователя в группу `docker` или нет.
- `docker_engine_group_user` — пользователь для добавления в группу `docker`.
- `docker_engine_validate_installation` — включить или выключить verify-задачи.
- `docker_engine_gpg_fingerprint` — ожидаемый fingerprint Docker GPG key.
- `docker_engine_gpg_key_checksum` — опциональный checksum для проверки целостности ключа при скачивании.

## Использование

```yaml
- hosts: docker_hosts
  become: true
  roles:
    - docker_engine
```

## Поведение

Роль работает по принципу `fail-fast` и завершится ошибкой на неподдерживаемой ОС или невалидных параметрах репозитория.

Повторный запуск не должен ничего менять на хосте без необходимости.

Verify-задачи выполняются только при `docker_engine_validate_installation: true`.

После скачивания роль проверяет fingerprint Docker GPG key, а при задании `docker_engine_gpg_key_checksum` дополнительно проверяет checksum.

## После деплоя

Если включен `docker_engine_manage_user_group: true`, роль добавляет пользователя в группу `docker`, новые права обычно применяются только в новой сессии.

Чтобы права применились:

1. Завершите текущую SSH-сессию.
2. Подключитесь к хосту заново.
3. Проверьте:
   - `id -nG` (в списке должна быть группа `docker`)
   - `docker ps` (должно работать без `sudo`)

Если `docker` в группах не появился, проверьте значение `docker_engine_group_user` и повторно запустите роль.

## Быстрая проверка

```bash
docker --version
docker compose version
systemctl is-enabled docker
systemctl is-active docker
```

Автопроверки в роли выполняются только при `docker_engine_validate_installation: true`.
