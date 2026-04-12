# common

Роль с минимальным OS-baseline для VM k3s. Все остальные роли запускаются после `common` и предполагают, что базовая подготовка хоста уже выполнена.

## Структура роли

```text
.
├── README.md
├── defaults/main.yml
└── tasks/
    ├── main.yml
    ├── validate.yml
    ├── packages.yml
    ├── filesystem.yml
    ├── timezone.yml
    └── verify.yml
```

## Что делает

- Проверяет, что хост относится к поддерживаемому семейству/дистрибутиву:
  - `ansible_os_family: Debian`
  - `ansible_distribution: Ubuntu`
- Обновляет apt cache (с retry/lock параметрами из defaults).
- Устанавливает базовые пакеты:
  - `ca-certificates`
  - `curl`
  - `tzdata`
- Создает базовые директории:
  - `/etc/modules-load.d`
  - `/etc/sysctl.d`
- Опционально настраивает timezone.
- Выполняет verify-блок после apply:
  - проверяет, что пакеты действительно установлены;
  - проверяет существование baseline директорий;
  - проверяет текущую timezone (если управление timezone включено).

## Граница ответственности

`common` в bootstrap-этапе делает только общий системный baseline.

Роль **не** управляет:

- firewall правилами;
- установкой k3s и настройкой кластера.

## Переменные

Основные переменные из `defaults/main.yml`:

- `common_supported_os_families` - поддерживаемые OS family.
- `common_supported_distributions` - поддерживаемые дистрибутивы.
- `common_packages_common` - базовые пакеты.
- `common_apt_cache_valid_time` - время валидности apt cache.
- `common_apt_lock_timeout` - timeout ожидания apt lock.
- `common_apt_update_cache_retries` - retries для apt cache update.
- `common_apt_update_cache_retry_max_delay` - max delay между retries.
- `common_directories` - baseline директории, которые должны существовать.
- `common_manage_timezone` - включить/выключить управление timezone.
- `common_timezone` - целевая timezone.

## Использование

```yaml
- hosts: k3s_hosts
  become: true
  roles:
    - common
```

## Поведение

- Роль работает в fail-fast режиме на неподдерживаемой ОС.
- Повторный запуск идемпотентен.
- Verify-блок выполняется только в обычном прогоне (не в `--check`).

## Быстрая проверка

```bash
cd deploy/kubernetes/bootstrap

ansible -i inventories/cloud/hosts.yml k3s_hosts -b -m shell -a "curl --version"
ansible -i inventories/cloud/hosts.yml k3s_hosts -b -m shell -a "ls -ld /etc/modules-load.d /etc/sysctl.d"
ansible -i inventories/cloud/hosts.yml k3s_hosts -b -m shell -a "timedatectl show -p Timezone --value"
```
