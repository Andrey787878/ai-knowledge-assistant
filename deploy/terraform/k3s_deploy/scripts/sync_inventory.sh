#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
INVENTORY_FILE="${TF_DIR}/../../kubernetes/bootstrap/inventories/cloud/hosts.yml"

cd "${TF_DIR}"
terraform output -raw ansible_inventory_yaml > "${INVENTORY_FILE}"

echo "Updated inventory: ${INVENTORY_FILE}"