#!/bin/bash

# Doppler Manager - Secret Manager Auto-Detection
# Automatically detects available secret managers and selects the best one

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the interface
source "${SCRIPT_DIR}/secret_manager_interface.sh"

# Detection priority (higher number = higher priority)
declare -A DETECTION_PRIORITY=(
    ["doppler"]=100
    ["vault"]=80
    ["aws_secrets"]=60
    ["gcp_secret"]=40
    ["azure_key"]=30
    ["infisical"]=70
)

# Detection results
declare -A DETECTED_MANAGERS=()
declare -A DETECTION_REASONS=()

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[PASS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================
# DETECTION FUNCTIONS
# ============================================

# detect_doppler() - Detect Doppler CLI
detect_doppler() {
    if command -v doppler &> /dev/null; then
        # Check if configured
        if doppler configure &>/dev/null; then
            DETECTED_MANAGERS["doppler"]="${SCRIPT_DIR}/managers/doppler.sh"
            DETECTION_REASONS["doppler"]="Doppler CLI installed and authenticated"

            # Get token type for additional info
            local token_type
            token_type=$(doppler configure get token --plain 2>/dev/null | cut -d. -f1-2 || echo "")
            if [[ "$token_type" == "dp.st" ]]; then
                DETECTION_REASONS["doppler"]="${DETECTION_REASONS["doppler"]} (Service Token)"
            elif [[ "$token_type" == "dp.pt" ]]; then
                DETECTION_REASONS["doppler"]="${DETECTION_REASONS["doppler"]} (Personal Token)"
            fi

            return 0
        else
            DETECTION_REASONS["doppler"]="Doppler CLI installed but not authenticated"
            return 1
        fi
    fi

    DETECTION_REASONS["doppler"]="Doppler CLI not found in PATH"
    return 1
}

# detect_vault() - Detect HashiCorp Vault
detect_vault() {
    if command -v vault &> /dev/null; then
        # Check if VAULT_ADDR is set and vault is reachable
        if [[ -n "${VAULT_ADDR:-}" ]]; then
            if vault status &>/dev/null; then
                DETECTED_MANAGERS["vault"]="${SCRIPT_DIR}/managers/vault.sh"
                DETECTION_REASONS["vault"]="Vault CLI installed and reachable at $VAULT_ADDR"
                return 0
            else
                DETECTION_REASONS["vault"]="Vault CLI installed but cannot reach $VAULT_ADDR"
                return 1
            fi
        else
            DETECTION_REASONS["vault"]="Vault CLI installed but VAULT_ADDR not set"
            return 1
        fi
    fi

    DETECTION_REASONS["vault"]="Vault CLI not found in PATH"
    return 1
}

# detect_aws_secrets() - Detect AWS Secrets Manager
detect_aws_secrets() {
    if command -v aws &> /dev/null; then
        # Check if AWS credentials are configured
        if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]] && [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
            DETECTED_MANAGERS["aws_secrets"]="${SCRIPT_DIR}/managers/aws_secrets.sh"
            DETECTION_REASONS["aws_secrets"]="AWS CLI configured with Access Key"

            # Check for specific region if set
            if [[ -n "${AWS_DEFAULT_REGION:-}" ]]; then
                DETECTION_REASONS["aws_secrets"]="${DETECTION_REASONS["aws_secrets"]} in ${AWS_DEFAULT_REGION}"
            fi

            return 0
        elif [[ -f "${HOME}/.aws/credentials" ]] || [[ -f "${HOME}/.aws/config" ]]; then
            DETECTED_MANAGERS["aws_secrets"]="${SCRIPT_DIR}/managers/aws_secrets.sh"
            DETECTION_REASONS["aws_secrets"]="AWS CLI configured with shared credentials file"
            return 0
        else
            DETECTION_REASONS["aws_secrets"]="AWS CLI installed but no credentials found"
            return 1
        fi
    fi

    DETECTION_REASONS["aws_secrets"]="AWS CLI not found in PATH"
    return 1
}

# detect_gcp_secret() - Detect GCP Secret Manager
detect_gcp_secret() {
    if command -v gcloud &> /dev/null; then
        # Check if authenticated with GCP
        if gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q "@"; then
            DETECTED_MANAGERS["gcp_secret"]="${SCRIPT_DIR}/managers/gcp_secret.sh"
            DETECTION_REASONS["gcp_secret"]="gcloud authenticated and configured"
            return 0
        else
            DETECTION_REASONS["gcp_secret"]="gcloud CLI installed but not authenticated"
            return 1
        fi
    fi

    DETECTION_REASONS["gcp_secret"]="gcloud CLI not found in PATH"
    return 1
}

# detect_azure_key() - Detect Azure Key Vault
detect_azure_key() {
    if command -v az &> /dev/null; then
        # Check if Azure CLI is logged in
        if az account show &>/dev/null; then
            local subscription
            subscription=$(az account show --query name -o tsv 2>/dev/null || echo "unknown")
            DETECTED_MANAGERS["azure_key"]="${SCRIPT_DIR}/managers/azure_key.sh"
            DETECTION_REASONS["azure_key"]="Azure CLI logged in to subscription: $subscription"
            return 0
        else
            DETECTION_REASONS["azure_key"]="Azure CLI installed but not logged in"
            return 1
        fi
    fi

    DETECTION_REASONS["azure_key"]="Azure CLI (az) not found in PATH"
    return 1
}

# detect_infisical() - Detect Infisical CLI
detect_infisical() {
    # Check for 'infisical' or 'fi' CLI
    local cli=""
    if command -v infisical &> /dev/null; then
        cli="infisical"
    elif command -v fi &> /dev/null; then
        cli="fi"
    fi

    if [[ -n "$cli" ]]; then
        # Check if authenticated by trying to list secrets
        if $cli secrets list --limit 1 &>/dev/null; then
            DETECTED_MANAGERS["infisical"]="${SCRIPT_DIR}/managers/infisical.sh"
            DETECTION_REASONS["infisical"]="Infisical CLI installed and authenticated"
            return 0
        else
            DETECTION_REASONS["infisical"]="Infisical CLI installed but not authenticated"
            return 1
        fi
    fi

    DETECTION_REASONS["infisical"]="Infisical CLI not found in PATH"
    return 1
}

# ============================================
# MAIN DETECTION LOGIC
# ============================================

# detect_all() - Run all detection functions
detect_all() {
    info "Detecting available secret managers..."
    echo ""

    detect_doppler
    detect_vault
    detect_aws_secrets
    detect_gcp_secret
    detect_azure_key
    detect_infisical

    echo ""
}

# select_best_manager() - Select the best available manager
# Returns: manager name (or empty if none)
select_best_manager() {
    local best_manager=""
    local best_priority=-1

    for manager in "${!DETECTED_MANAGERS[@]}"; do
        local priority="${DETECTION_PRIORITY[$manager]:-0}"

        if [[ "$priority" -gt "$best_priority" ]]; then
            best_priority="$priority"
            best_manager="$manager"
        fi
    done

    echo "$best_manager"
}

# ============================================
# OUTPUT FORMATTING
# ============================================

# print_detection_report() - Print a formatted detection report
print_detection_report() {
    echo "=============================================="
    echo "  Secret Manager Detection Report"
    echo "=============================================="
    echo ""

    if [[ ${#DETECTED_MANAGERS[@]} -eq 0 ]]; then
        error "No secret managers detected!"
        echo ""
        echo "Available secret managers:"
        echo "  - Doppler (dopplerhq.com) - Run 'doppler login'"
        echo "  - HashiCorp Vault - Set VAULT_ADDR environment variable"
        echo "  - AWS Secrets Manager - Configure AWS credentials"
        echo "  - GCP Secret Manager - Run 'gcloud auth login'"
        echo "  - Azure Key Vault - Run 'az login'"
        echo "  - Infisical - Run 'infisical login'"
        echo ""
        return 1
    fi

    echo "Detected Secret Managers:"
    echo ""

    # Sort by priority
    declare -a sorted_managers
    IFS=' ' sorted_managers=($(for m in "${!DETECTED_MANAGERS[@]}"; do echo "$m"; done | sort -t'\0' -n))
    unset IFS

    for manager in "${sorted_managers[@]}"; do
        local priority="${DETECTION_PRIORITY[$manager]:-0}"
        printf "  %-15s [Priority: %3d] %s\n" "$manager" "$priority" "${DETECTION_REASONS[$manager]}"
    done

    echo ""

    local best
    best=$(select_best_manager)

    if [[ -n "$best" ]]; then
        success "Best available manager: $best"
        echo ""
        echo "To use this manager, either:"
        echo "  1. Let the skill auto-select (recommended)"
        echo "  2. Explicitly load it:"
        echo "     source ${SCRIPT_DIR}/secret_manager_interface.sh"
        echo "     sm_load $best"
        echo ""
    fi

    return 0
}

# print_json_output() - Print detection results as JSON
print_json_output() {
    local best
    best=$(select_best_manager)

    local managers_json="["
    local first=true
    for manager in "${!DETECTED_MANAGERS[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            managers_json+=","
        fi
        local priority="${DETECTION_PRIORITY[$manager]:-0}"
        managers_json+=$(cat <<EOF
{
  "name": "$manager",
  "script": "${DETECTED_MANAGERS[$manager]}",
  "priority": $priority,
  "reason": "${DETECTION_REASONS[$manager]}",
  "selected": $([ "$manager" == "$best" ] && echo "true" || echo "false")
}
EOF
)
    done
    managers_json+="]"

    cat <<EOF
{
  "detected": $([ ${#DETECTED_MANAGERS[@]} -gt 0 ] && echo "true" || echo "false"),
  "count": ${#DETECTED_MANAGERS[@]},
  "best_manager": "${best}",
  "managers": ${managers_json}
}
EOF
}

# ============================================
# USAGE
# ============================================

usage() {
    cat <<EOF
Secret Manager Auto-Detection

Usage: $(basename "$0") [options]

Options:
  -h, --help              Show this help message
  -j, --json              Output in JSON format
  -q, --quiet             Only show detected managers
  -s, --select            Auto-select and load the best manager

Examples:
  $(basename "$0")                    # Show full detection report
  $(basename "$0") --json            # Output as JSON
  $(basename "$0") --select          # Auto-select best manager

Exit Codes:
  0 - At least one manager detected
  1 - No managers detected

EOF
}

# ============================================
# MAIN
# ============================================

main() {
    local output_mode="report"
    local auto_select=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -j|--json)
                output_mode="json"
                shift
                ;;
            -q|--quiet)
                output_mode="quiet"
                shift
                ;;
            -s|--select)
                auto_select=true
                shift
                ;;
            *)
                echo "Unknown option: $1" >&2
                usage
                exit 1
                ;;
        esac
    done

    # Run detection
    detect_all

    # Output based on mode
    case "$output_mode" in
        json)
            print_json_output
            ;;
        quiet)
            for manager in "${!DETECTED_MANAGERS[@]}"; do
                echo "$manager"
            done
            ;;
        *)
            print_detection_report
            ;;
    esac

    # Auto-select if requested
    if [[ "$auto_select" == "true" ]] && [[ ${#DETECTED_MANAGERS[@]} -gt 0 ]]; then
        local best
        best=$(select_best_manager)

        if [[ -n "$best" ]]; then
            echo ""
            info "Auto-loading best manager: $best"
            sm_load "$best"
        fi
    fi

    # Return success if at least one manager found
    if [[ ${#DETECTED_MANAGERS[@]} -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
