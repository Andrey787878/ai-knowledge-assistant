#!/usr/bin/env bash
set -Eeuo pipefail

KUBECTL_BIN="${KUBECTL_BIN:-kubectl}"
PG_NAMESPACE="${PG_NAMESPACE:-db}"
PG_RELEASE_NAME="${PG_RELEASE_NAME:-postgres}"
PG_SECRET_NAME="${PG_SECRET_NAME:-${PG_RELEASE_NAME}-postgresql}"
PG_SECRET_KEY="${PG_SECRET_KEY:-postgres-password}"
PG_USER="${PG_USER:-postgres}"
PG_BACKUP_DATABASES="${PG_BACKUP_DATABASES:-n8n wikijs}"

BACKUP_ROOT_DIR="${BACKUP_ROOT_DIR:-/var/backups/ai-agent/postgres}"
BACKUP_LOCK_FILE="${BACKUP_LOCK_FILE:-${BACKUP_ROOT_DIR}/.backup.lock}"
RESTORE_CONFIRM="${RESTORE_CONFIRM:-NO}"

BACKUP_DIR_INPUT="${1:-}"
WITH_GLOBALS="${2:-false}"

LOCK_ACQUIRED="false"
PG_POD=""

read -r -a BACKUP_DATABASES <<< "${PG_BACKUP_DATABASES}"

k() {
  "${KUBECTL_BIN}" -n "${PG_NAMESPACE}" "$@"
}

find_postgres_pod() {
  k get pods \
    -l "app.kubernetes.io/instance=${PG_RELEASE_NAME},app.kubernetes.io/name=postgresql" \
    -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}' \
    | head -n1
}

cleanup() {
  local rc=$?

  if [[ -n "${PG_POD}" ]]; then
    k exec "${PG_POD}" -- rm -f /tmp/globals.sql >/dev/null 2>&1 || true
    for db_name in "${BACKUP_DATABASES[@]}"; do
      k exec "${PG_POD}" -- rm -f "/tmp/${db_name}.dump" >/dev/null 2>&1 || true
    done
  fi

  if [[ "${LOCK_ACQUIRED}" == "true" ]]; then
    rm -f "${BACKUP_LOCK_FILE}" >/dev/null 2>&1 || true
  fi

  exit "${rc}"
}

trap cleanup EXIT INT TERM

if [[ "${RESTORE_CONFIRM}" != "YES" ]]; then
  echo "Set RESTORE_CONFIRM=YES to allow restore." >&2
  exit 1
fi

if [[ "${#BACKUP_DATABASES[@]}" -eq 0 ]]; then
  echo "PG_BACKUP_DATABASES must contain at least one database name." >&2
  exit 1
fi

if [[ -z "${BACKUP_DIR_INPUT}" ]]; then
  echo "usage: $0 <backup_dir|current> [with_globals:true|false]" >&2
  exit 1
fi

if [[ "${BACKUP_DIR_INPUT}" == "current" ]]; then
  BACKUP_DIR="${BACKUP_ROOT_DIR}/current"
else
  BACKUP_DIR="${BACKUP_DIR_INPUT}"
fi

if [[ ! -d "${BACKUP_DIR}" ]]; then
  echo "backup directory not found: ${BACKUP_DIR}" >&2
  exit 1
fi

if [[ ! -f "${BACKUP_DIR}/SHA256SUMS" ]]; then
  echo "SHA256SUMS not found in ${BACKUP_DIR}" >&2
  exit 1
fi

(
  cd "${BACKUP_DIR}"
  sha256sum -c SHA256SUMS
)

mkdir -p "$(dirname "${BACKUP_LOCK_FILE}")"

if [[ -f "${BACKUP_LOCK_FILE}" ]]; then
  LOCK_PID="$(cat "${BACKUP_LOCK_FILE}" 2>/dev/null || true)"
  if [[ -n "${LOCK_PID}" && "${LOCK_PID}" =~ ^[0-9]+$ ]] && kill -0 "${LOCK_PID}" 2>/dev/null; then
    echo "another postgres backup/restore process is running (pid: ${LOCK_PID})" >&2
    exit 1
  fi
  rm -f "${BACKUP_LOCK_FILE}" >/dev/null 2>&1 || true
fi

if ! (set -o noclobber; echo "$$" > "${BACKUP_LOCK_FILE}") 2>/dev/null; then
  echo "backup lock file exists: ${BACKUP_LOCK_FILE}" >&2
  exit 1
fi

LOCK_ACQUIRED="true"

PG_POD="$(find_postgres_pod)"
if [[ -z "${PG_POD}" ]]; then
  echo "postgres running pod not found in namespace '${PG_NAMESPACE}' for release '${PG_RELEASE_NAME}'." >&2
  exit 1
fi

PG_PASSWORD="$({ k get secret "${PG_SECRET_NAME}" -o "jsonpath={.data.${PG_SECRET_KEY}}" | base64 --decode; } 2>/dev/null)"
if [[ -z "${PG_PASSWORD}" ]]; then
  echo "cannot read postgres password from secret '${PG_SECRET_NAME}' key '${PG_SECRET_KEY}'." >&2
  exit 1
fi

if [[ "${WITH_GLOBALS}" == "true" ]]; then
  if [[ ! -f "${BACKUP_DIR}/globals.sql" ]]; then
    echo "globals.sql not found in ${BACKUP_DIR}" >&2
    exit 1
  fi
  k cp "${BACKUP_DIR}/globals.sql" "${PG_NAMESPACE}/${PG_POD}:/tmp/globals.sql"
  k exec "${PG_POD}" -- sh -eu -c 'PGPASSWORD="$1" psql -v ON_ERROR_STOP=1 -U "$2" -d postgres -f /tmp/globals.sql' sh "${PG_PASSWORD}" "${PG_USER}"
  k exec "${PG_POD}" -- rm -f /tmp/globals.sql
fi

for db_name in "${BACKUP_DATABASES[@]}"; do
  dump_file="${BACKUP_DIR}/${db_name}.dump"
  tmp_dump="/tmp/${db_name}.dump"

  if [[ ! -f "${dump_file}" ]]; then
    echo "dump not found: ${dump_file}" >&2
    exit 1
  fi

  k cp "${dump_file}" "${PG_NAMESPACE}/${PG_POD}:${tmp_dump}"
  k exec "${PG_POD}" -- sh -eu -c 'PGPASSWORD="$1" pg_restore --clean --if-exists -U "$2" -d "$3" "$4"' sh "${PG_PASSWORD}" "${PG_USER}" "${db_name}" "${tmp_dump}"
  k exec "${PG_POD}" -- rm -f "${tmp_dump}"
done

echo "postgres restore completed from: ${BACKUP_DIR}"
