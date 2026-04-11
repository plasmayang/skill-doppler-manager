#!/bin/bash

# Doppler Manager - AWS Secrets Manager Implementation
# Implements the secret manager interface for AWS Secrets Manager

set -euo pipefail

MANAGER_NAME="aws_secrets"
MANAGER_VERSION="1.0.0"

if [[ -z "${MANAGER_REGISTRY:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "${SCRIPT_DIR}/secret_manager_interface.sh" 2>/dev/null || true
fi

# sm_init() - Initialize AWS Secrets Manager CLI
sm_init() {
    sm_status
}

# sm_status() - Get AWS Secrets Manager status in JSON format
sm_status() {
    if ! command -v aws &> /dev/null; then
        cat <<EOF
{
  "status": "ERROR",
  "code": "E001",
  "message": "AWS CLI is not installed",
  "hint": "Install AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html",
  "documentation": "references/SOP.md#aws-setup",
  "project": null,
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
        return 1
    fi

    # Check for credentials
    if ! aws configure get aws_access_key_id &>/dev/null; then
        if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]] && [[ -z "${AWS_PROFILE:-}" ]]; then
            cat <<EOF
{
  "status": "ERROR",
  "code": "E002",
  "message": "AWS credentials not configured",
  "hint": "Run 'aws configure' or set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY",
  "documentation": "references/SOP.md#aws-setup",
  "project": null,
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
            return 1
        fi
    fi

    # Test connectivity
    local region="${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || echo 'us-east-1')}"
    if ! aws secretsmanager list-secrets --region "$region" --max-items 1 &>/dev/null; then
        cat <<EOF
{
  "status": "ERROR",
  "code": "E006",
  "message": "Cannot connect to AWS Secrets Manager",
  "hint": "Check AWS credentials and network connectivity",
  "documentation": "references/SOP.md#aws-setup",
  "project": null,
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
  "message": "AWS Secrets Manager is configured and reachable",
  "hint": "Use AWS CLI commands for secret operations",
  "documentation": "references/SOP.md#aws-setup",
  "project": "${region}",
  "config": null,
  "manager": "${MANAGER_NAME}"
}
EOF
    return 0
}

# sm_run() - Run command with AWS secrets injected
sm_run() {
    if [[ $# -eq 0 ]]; then
        echo "ERROR: sm_run requires a command to execute" >&2
        return 1
    fi

    if ! sm_is_configured 2>/dev/null; then
        echo "ERROR: AWS not configured. Set up credentials first." >&2
        return 1
    fi

    sm_audit "run" "INJECTED" "true"
    "$@"
}

# sm_get() - Get a single secret value from AWS Secrets Manager
sm_get() {
    local secret_name="${1:-}"

    if [[ -z "$secret_name" ]]; then
        echo "ERROR: sm_get requires a secret name" >&2
        return 1
    fi

    if ! sm_is_configured 2>/dev/null; then
        echo "ERROR: AWS not configured" >&2
        return 1
    fi

    local region="${AWS_DEFAULT_REGION:-us-east-1}"
    local value
    value=$(aws secretsmanager get-secret-value --region "$region" --secret-id "$secret_name" --query SecretString --output text 2>/dev/null) || {
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

    echo "aws secretsmanager put-secret-value --secret-id ${secret_name} --secret-string '<value>'"
    echo ""
    echo "Run the above command in your terminal to set the secret."
    echo "The AI agent will wait for you to confirm completion."

    return 0
}

sm_is_configured() {
    command -v aws &> /dev/null && (aws configure get aws_access_key_id &>/dev/null || [[ -n "${AWS_ACCESS_KEY_ID:-}" ]])
}

export -f sm_init sm_status sm_run sm_get sm_audit sm_set sm_is_configured
