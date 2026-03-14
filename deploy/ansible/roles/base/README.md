# base

Базовый OS-baseline для всех VM перед сервисными ролями.

## Что делает

- Проверяет, что `ansible_os_family` поддерживается.
- Обновляет кеш пакетного менеджера:
  - `apt` для `Debian` family
  - `dnf` для `RedHat` family
- Устанавливает пакеты из `base_packages`.
- Опционально настраивает timezone.

## Что роль не делает

- Не создает проектные директории.
- Не устанавливает Docker.
- Не деплоит прикладные сервисы.

## Переменные

Значения по умолчанию задаются в `defaults/main.yml`:

- `base_supported_os_families` - поддерживаемые семейства ОС.
- `base_packages` - список базовых пакетов.
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
timedatectl show -p Timezone --value
```

Проверка timezone актуальна при включенном управлении timezone.
