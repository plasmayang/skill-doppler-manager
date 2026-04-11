#!/bin/bash

# Doppler Manager - Azure Key Vault Implementation
# Implements the secret manager interface for Azure Key Vault

set -euo pipefail

MANAGER_NAME="azure_key"
MANAGER_VERSION="1.0.0"

if [[ -z "${MANAGER_REGISTRY:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "${SCRIPT_DIR}/secret_manager_interface.sh" 2>/dev/null || true
fi

# sm_init() - Initialize Azure Key Vault CLI
sm_init() {
    sm_status
}

# sm_status() - Get Azure Key Vault status in JSON format
sm_status() {
    if ! command -v az &> /dev/null; then
        cat <<EOF
{
  "status": "ERROR",
  "code": "E001",
  "message": "Azure CLI (az) is not installed",
  "hint": "Install Azure CLI: https://docs.microsoft.com/cli/azure/install-azure-cli",
  "documentation": "references/SOP.md#azure-setup",
  "project": null,
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
        return 1
    fi

    # Check if logged in
    local account
    account=$(az account show --query name -o tsv 2>/dev/null) || {
        cat <<EOF
{
  "status": "ERROR",
  "code": "E002",
  "message": "Azure CLI is not logged in",
  "hint": "Run 'az login' to authenticate",
  "documentation": "references/SOP.md#azure-setup",
  "project": null,
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
        return 1
    }

    if [[ -z "$account" ]]; then
        cat <<EOF
{
  "status": "ERROR",
  "code": "E002",
  "message": "No active Azure subscription found",
  "hint": "Run 'az login' to authenticate",
  "documentation": "references/SOP.md#azure-setup",
  "project": null,
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
        return 1
    fi

    local subscription_id
    subscription_id=$(az account show --query id -o tsv 2>/dev/null)

    cat <<EOF
{
  "status": "OK",
  "code": "E000",
  "message": "Azure CLI is authenticated",
  "hint": "Use 'az keyvault' commands for secret operations",
  "documentation": "references/SOP.md#azure-setup",
  "project": "${subscription_id}",
  "config": "${account}",
  "manager": "${MANAGER_NAME}"
}
EOF
    return 0
}

# sm_run() - Run command with Azure Key Vault secrets injected
sm_run() {
    if [[ $# -eq 0 ]]; then
        echo "ERROR: sm_run requires a command to execute" >&2
        return 1
    fi

    if ! sm_is_configured 2>/dev/null; then
        echo "ERROR: Azure CLI not configured. Run 'az login' first." >&2
        return 1
    fi

    sm_audit "run" "INJECTED" "true"
    "$@"
}

# sm_get() - Get a single secret value from Azure Key Vault
sm_get() {
    local secret_ref="${1:-}"  # Format: vault-name/secret-name[/version]

    if [[ -z "$secret_ref" ]]; then
        echo "ERROR: sm_get requires a secret reference (vault-name/secret-name)" >&2
        return 1
    fi

    if ! sm_is_configured 2>/dev/null; then
        echo "ERROR: Azure CLI not configured" >&2
        return 1
    fi

    local vault_name secret_name
    vault_name=$(echo "$secret_ref" | cut -d/ -f1)
    secret_name=$(echo "$secret_ref" | cut -d/ -f2)

    if [[ -z "$vault_name" ]] || [[ -z "$secret_name" ]]; then
        echo "ERROR: Invalid secret reference format. Use: vault-name/secret-name" >&2
        return 1
    fi

    local value
    value=$(az keyvault secret show --vault-name "$vault_name" --name "$secret_name" --query value -o tsv 2>/dev/null) || {
        echo "ERROR: Secret '$secret_ref' not found or inaccessible" >&2
        return 1
    }

    echo "$value"
    sm_audit "get" "$secret_ref" "true"
    return 0
}

# sm_audit() - Log secret access event
sm_audit() {
    local event_type="${1:-}"
    local secret_name="${2:-}"
    local success="${3:-true}"

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    if [[ -f "${script_dir}/audit_secrets.sh" ]]; then
        bash "${script_dir}/audit_secrets.sh" access "$secret_name" "sm_${event_type}" "$success" 2>/dev/null || true
    fi
}

# sm_set() - Prepare a command for setting a secret (HITL pattern)
sm_set() {
    local secret_ref="${1:-}"

    if [[ -z "$secret_ref" ]]; then
        echo "ERROR: sm_set requires a secret reference" >&2
        return 1
    fi

    local vault_name secret_name
    vault_name=$(echo "$secret_ref" | cut -d/ -f1)
    secret_name=$(echo "$secret_ref" | cut -d/ -f2)

    echo "az keyvault secret set --vault-name ${vault_name} --name ${secret_name} --value '<value>'"
    echo ""
    echo "Run the above command in your terminal to set the secret."
    echo "The AI agent will wait for you to confirm completion."

    return 0
}

sm_is_configured() {
    command -v az &> /dev/null && az account show &>/dev/null
}

export -f sm_init sm_status sm_run sm_get sm_audit sm_set sm_is_configured
