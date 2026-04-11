# common

Роль с общим OS-baseline для всех VM перед сервисными ролями. Все сервисные роли запускаются после `common` и предполагают, что базовая подготовка хоста уже выполнена.

## Структура роли

```text
.
├── README.md
├── defaults/main.yml
├── handlers/main.yml
├── tasks/
│   ├── main.yml
│   ├── validate.yml
│   ├── packages.yml
│   ├── filesystem.yml
│   ├── automation_user.yml
│   ├── ssh_hardening.yml
│   ├── timezone.yml
│   └── verify.yml
└── templates/
    ├── 90-automation-user.sudoers.j2
    └── 99-common-hardening.conf.j2
```

## Что делает

- Проверяет, что `ansible_os_family` поддерживается.
- Обновляет кеш пакетного менеджера:
  - `apt` для `Debian` family
  - `dnf` для `RedHat` family
- Устанавливает базовые пакеты:
  - общие: `common_packages_common`
  - платформенные: `common_packages_debian` / `common_packages_redhat`
- Создает базовые директории из `common_directories` (по умолчанию `/opt/ai-agent`).
- Управляет automation-user baseline:
  - user/groups/shell/home,
  - `sudoers.d` policy с `visudo`-валидацией.
- Применяет базовый SSH-hardening через `sshd_config.d` drop-in:
  - `PubkeyAuthentication`
  - `PasswordAuthentication`
  - `PermitRootLogin`
  - `KbdInteractiveAuthentication`
    с валидацией `sshd -t` перед `reload`.
- Опционально настраивает timezone.
- Выполняет verify-блок после apply:
  - effective SSH policy через `sshd -T`,
  - sudo-policy check (`visudo -cf`, mode/owner, expected rule).

## Граница ответственности

`common` выполняет только общесистемный baseline для всех VM (пакеты, базовые директории, automation-user, SSH, timezone).

## Переменные

Значения по умолчанию задаются в `defaults/main.yml`:

- `common_supported_os_families` - поддерживаемые семейства ОС.
- `common_packages_common` - список базовых пакетов для всех поддерживаемых платформ.
- `common_packages_debian` - список базовых пакетов для `Debian` family.
- `common_packages_redhat` - список базовых пакетов для `RedHat` family.
- `common_directories` - список базовых директорий, которые должны существовать на хосте.
- `common_manage_automation_user` - включить или выключить управление automation-user.
- `common_automation_user_name` - имя automation-пользователя (по умолчанию `ansible_user`).
- `common_automation_user_shell` - shell пользователя.
- `common_automation_user_create_home` - создавать home-директорию пользователя.
- `common_automation_user_groups_map` / `common_automation_user_groups` - базовые группы пользователя.
- `common_automation_user_append_groups` - добавлять группы, не перезаписывая существующие.
- `common_automation_user_manage_sudo` - управлять ли sudo policy для automation-user.
- `common_automation_user_sudo_nopasswd` - давать `NOPASSWD` для automation-user.
- `common_automation_user_sudo_commands` - список/шаблон sudo-команд (обычно `ALL`).
- `common_automation_user_sudo_file` - путь файла в `/etc/sudoers.d`.
- `common_visudo_binary_path` - путь к `visudo` для валидации и verify sudoers.
- `common_manage_ssh_hardening` - включить или выключить SSH-hardening в роли `common`.
- `common_sshd_manage_dropin_include` - добавлять ли строку `Include /etc/ssh/sshd_config.d/*.conf` в `/etc/ssh/sshd_config`.
- `common_sshd_dropin_dir` - директория для SSH drop-in файлов.
- `common_sshd_dropin_file` - путь до управляемого drop-in файла с SSH политиками.
- `common_sshd_pubkey_authentication` - значение `PubkeyAuthentication` (`yes`/`no`).
- `common_sshd_password_authentication` - значение `PasswordAuthentication` (`yes`/`no`).
- `common_sshd_permit_root_login` - значение `PermitRootLogin` (`no`, `yes`, `prohibit-password`, `forced-commands-only`).
- `common_sshd_kbd_interactive_authentication` - значение `KbdInteractiveAuthentication` (`yes`/`no`).
- `common_ssh_hardening_allow_root_ansible_user` - аварийный override, если подключение Ansible идет под `root`.
- `common_sshd_binary_path` - путь до бинарника `sshd` для `sshd -t`.
- `common_sshd_service_name_map` / `common_sshd_service_name` - имя SSH сервиса для `reload`.
- `common_manage_timezone` - включить или выключить управление timezone.
- `common_timezone` - timezone, которая будет установлена только при `common_manage_timezone: true`.

## Использование

```yaml
- hosts: all
  become: true
  roles:
    - common
```

## Поведение

Роль работает по принципу `fail-fast` и завершится ошибкой на неподдерживаемой ОС.

Повторный запуск не должен ничего менять на хосте без необходимости.

Timezone не меняется, пока `common_manage_timezone` не включен.

При `common_manage_timezone: true` роль дополнительно валидирует `common_timezone`.

Automation-user baseline применяется только при `common_manage_automation_user: true`.

SSH hardening применяется только при `common_manage_ssh_hardening: true`.

Если в Ansible используется `root`-подключение и одновременно задан `PermitRootLogin no`,
роль остановится заранее с понятной ошибкой (fail-fast guard от lockout).

Verify-блок выполняется в обычном запуске (не в `--check`), чтобы проверить
effective SSH и sudo-policy после применения.

## Быстрая проверка

SSH-вариант (опционально): для ручного дебага см. [раздел в основном runbook](../../README.md#manual-ssh).

Команды ниже предполагают, что в текущей shell-сессии уже задан `ANSIBLE_VAULT_PASSWORD_FILE` (см. `deploy/ansible/README.md`, шаг 3).

```bash
cd deploy/ansible
ansible -i inventories/cloud/hosts.yml all -b -J -m shell -a "curl --version"
ansible -i inventories/cloud/hosts.yml all -b -J -m shell -a "ls -ld /opt/ai-agent"
ansible -i inventories/cloud/hosts.yml all -b -J -m shell -a "sshd -t"
ansible -i inventories/cloud/hosts.yml all -b -J -m shell -a "timedatectl show -p Timezone --value"
```

Проверка timezone актуальна при включенном управлении timezone.
