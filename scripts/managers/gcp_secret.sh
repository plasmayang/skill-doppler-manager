#!/bin/bash

# Doppler Manager - GCP Secret Manager Implementation
# Implements the secret manager interface for Google Cloud Secret Manager

set -euo pipefail

MANAGER_NAME="gcp_secret"
MANAGER_VERSION="1.0.0"

if [[ -z "${MANAGER_REGISTRY:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "${SCRIPT_DIR}/secret_manager_interface.sh" 2>/dev/null || true
fi

# sm_init() - Initialize GCP Secret Manager CLI
sm_init() {
    sm_status
}

# sm_status() - Get GCP Secret Manager status in JSON format
sm_status() {
    if ! command -v gcloud &> /dev/null; then
        cat <<EOF
{
  "status": "ERROR",
  "code": "E001",
  "message": "Google Cloud CLI (gcloud) is not installed",
  "hint": "Install gcloud CLI: https://cloud.google.com/sdk/docs/install",
  "documentation": "references/SOP.md#gcp-setup",
  "project": null,
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
        return 1
    fi

    # Check authentication
    local active_account
    active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1) || {
        cat <<EOF
{
  "status": "ERROR",
  "code": "E002",
  "message": "gcloud is not authenticated",
  "hint": "Run 'gcloud auth login' to authenticate",
  "documentation": "references/SOP.md#gcp-setup",
  "project": null,
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
        return 1
    }

    if [[ -z "$active_account" ]]; then
        cat <<EOF
{
  "status": "ERROR",
  "code": "E002",
  "message": "No active gcloud account found",
  "hint": "Run 'gcloud auth login' to authenticate",
  "documentation": "references/SOP.md#gcp-setup",
  "project": null,
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
        return 1
    fi

    local project="${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
    if [[ -z "$project" ]] || [[ "$project" == "(unset)" ]]; then
        cat <<EOF
{
  "status": "WARNING",
  "code": "E004",
  "message": "GCP project not configured",
  "hint": "Run 'gcloud config set project <project-id>'",
  "documentation": "references/SOP.md#gcp-setup",
  "project": null,
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
        return 0
    fi

    # Test connectivity to Secret Manager API
    if ! gcloud secrets list --limit 1 &>/dev/null; then
        cat <<EOF
{
  "status": "ERROR",
  "code": "E006",
  "message": "Cannot access GCP Secret Manager API",
  "hint": "Enable Secret Manager API and check permissions",
  "documentation": "references/SOP.md#gcp-setup",
  "project": "${project}",
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
        return 1
    fi

    cat <<EOF
{
  "status": "OK",
  "code": "E000",
  "message": "GCP Secret Manager is configured and reachable",
  "hint": "Use 'gcloud secrets' commands for secret operations",
  "documentation": "references/SOP.md#gcp-setup",
  "project": "${project}",
  "config": "${active_account}",
  "manager": "${MANAGER_NAME}"
}
EOF
    return 0
}

# sm_run() - Run command with GCP secrets injected
sm_run() {
    if [[ $# -eq 0 ]]; then
        echo "ERROR: sm_run requires a command to execute" >&2
        return 1
    fi

    if ! sm_is_configured 2>/dev/null; then
        echo "ERROR: GCP Secret Manager not configured." >&2
        return 1
    fi

    sm_audit "run" "INJECTED" "true"
    "$@"
}

# sm_get() - Get a single secret value from GCP Secret Manager
sm_get() {
    local secret_name="${1:-}"

    if [[ -z "$secret_name" ]]; then
        echo "ERROR: sm_get requires a secret name" >&2
        return 1
    fi

    if ! sm_is_configured 2>/dev/null; then
        echo "ERROR: GCP Secret Manager not configured" >&2
        return 1
    fi

    local project="${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
    local version="${2:-latest}"
    local value
    value=$(gcloud secrets versions access "$version" --secret="$secret_name" --project="$project" 2>/dev/null) || {
        echo "ERROR: Secret '$secret_name' not found or inaccessible" >&2
        return 1
    }

    echo "$value"
    sm_audit "get" "$secret_name" "true"
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
    local secret_name="${1:-}"

    if [[ -z "$secret_name" ]]; then
        echo "ERROR: sm_set requires a secret name" >&2
        return 1
    fi

    local project="${GCP_PROJECT_ID:-}"
    echo "echo -n '<value>' | gcloud secrets create ${secret_name} --data-file=- --replication-policy=automatic${project:+" --project=$project"}"
    echo ""
    echo "Run the above command in your terminal to set the secret."
    echo "The AI agent will wait for you to confirm completion."

    return 0
}

sm_is_configured() {
    command -v gcloud &> /dev/null && gcloud auth list --filter=status:ACTIVE &>/dev/null
}

export -f sm_init sm_status sm_run sm_get sm_audit sm_set sm_is_configured
