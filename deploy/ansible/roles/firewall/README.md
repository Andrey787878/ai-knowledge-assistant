# firewall

Роль для применения входящих правил firewalld на каждой VM.

## Структура роли

```text
.
├── README.md
├── defaults/main.yml
├── handlers/main.yml
└── tasks/
    ├── main.yml
    ├── validate.yml
    ├── firewalld.yml
    ├── strict_reconcile.yml
    └── verify.yml
```

## Что делает

- Валидирует переменные и структуру правил.
- Настраивает baseline firewall:
  - zone target `DROP` (deny-by-default inbound)
  - allow SSH только по source-списку.
- Применяет host-specific allow-list (`firewall_rules`) только с source CIDR (без broad правил).
- Проверяет, что firewalld запущен.
- Привязывает интерфейсы к зоне:
  - явный список `firewall_firewalld_interfaces`, либо
  - авто-детект `ansible_default_ipv4.interface` при пустом списке.
- Проверяет effective policy (`list-ports`/`list-services`/`list-rich-rules`/`--get-target`) и детектирует drift.

## Предусловия

- Хосты должны иметь корректные `private_ip` в inventory.
- Для применения правил требуется коллекция `ansible.posix` (`firewalld` module).
- На Debian/Ubuntu роль отключает `ufw`, чтобы не было конфликта с firewalld.

## Граница ответственности

`firewall` отвечает только за firewall на уровне VM.
Cloud Security Groups/ACL остаются отдельным слоем и должны быть синхронизированы с этими правилами.

## Переменные

Ключевые:

- `firewall_manage_ssh`, `firewall_ssh_port`, `firewall_ssh_sources`
- `firewall_rules` — список разрешенных inbound-правил (каждое правило обязано содержать `source` или `sources`).
- `firewall_firewalld_*` — параметры backend firewalld.
- `firewall_firewalld_interfaces` — явный список интерфейсов для привязки к `firewall_firewalld_zone`.
- `firewall_autodetect_default_interface` — при пустом `firewall_firewalld_interfaces` использовать `ansible_default_ipv4.interface`.
- `firewall_effective_interfaces` — вычисленный список интерфейсов, который реально применяется и верифицируется.
- `firewall_ipv4_cidr_regex` — валидация IPv4 CIDR для source-правил.

Пример `firewall_rules`:

```yaml
firewall_rules:
  - port: 443
    proto: tcp
    source: 10.10.0.12/32
```

Пример с несколькими source CIDR для одного порта:

```yaml
firewall_rules:
  - port: 443
    proto: tcp
    sources:
      - 198.51.100.10/32
      - 203.0.113.0/24
```

## Использование

```yaml
- hosts: all
  become: true
  roles:
    - firewall
```

Strict reconcile (purge drift + apply только декларативных правил):

```bash
cd deploy/ansible
ansible-playbook -i inventories/cloud/hosts.yml playbooks/firewall_reconcile_strict.yml
```

## Быстрая проверка

SSH-вариант (опционально): для ручного дебага см. [раздел в основном runbook](../../README.md#manual-ssh).

Команды ниже предполагают, что в текущей shell-сессии уже задан `ANSIBLE_VAULT_PASSWORD_FILE` (см. `deploy/ansible/README.md`, шаг 3).

```bash
cd deploy/ansible
ansible -i inventories/cloud/hosts.yml all -b -J -m shell -a "firewall-cmd --state"
ansible -i inventories/cloud/hosts.yml all -b -J -m shell -a "firewall-cmd --get-active-zones"
ansible -i inventories/cloud/hosts.yml all -b -J -m shell -a "firewall-cmd --list-all"
ansible -i inventories/cloud/hosts.yml all -b -J -m shell -a "firewall-cmd --list-rich-rules"
```
