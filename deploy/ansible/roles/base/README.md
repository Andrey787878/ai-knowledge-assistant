# base

Базовый OS-baseline для всех VM перед сервисными ролями. Все сервисные роли запускаются после `base` и предполагают, что базовая подготовка хоста уже выполнена.

## Что делает

- Проверяет, что `ansible_os_family` поддерживается.
- Обновляет кеш пакетного менеджера:
  - `apt` для `Debian` family
  - `dnf` для `RedHat` family
- Устанавливает базовые пакеты:
  - общие: `base_packages_common`
  - платформенные: `base_packages_debian` / `base_packages_redhat`
- Создает базовые директории из `base_directories` (по умолчанию `/opt/ai-agent`).
- Опционально настраивает timezone.

## Граница ответственности

`base` выполняет общесистемный baseline для всех VM (пакеты, базовые директории, timezone).

## Переменные

Значения по умолчанию задаются в `defaults/main.yml`:

- `base_supported_os_families` - поддерживаемые семейства ОС.
- `base_packages_common` - список базовых пакетов для всех поддерживаемых платформ.
- `base_packages_debian` - список базовых пакетов для `Debian` family.
- `base_packages_redhat` - список базовых пакетов для `RedHat` family.
- `base_directories` - список базовых директорий, которые должны существовать на хосте.
- `base_manage_timezone` - включить или выключить управление timezone.
- `base_timezone` - timezone, которая будет установлена только при `base_manage_timezone: true`.

## Использование

```yaml
- hosts: all
  become: true
  roles:
    - base
```

## Поведение

Роль работает по принципу `fail-fast` и завершится ошибкой на неподдерживаемой ОС.

Повторный запуск не должен ничего менять на хосте без необходимости.

Timezone не меняется, пока `base_manage_timezone` не включен.

При `base_manage_timezone: true` роль дополнительно валидирует `base_timezone`.

## Быстрая проверка

```bash
curl --version
ls -ld /opt/ai-agent
timedatectl show -p Timezone --value
```

Проверка timezone актуальна при включенном управлении timezone.
