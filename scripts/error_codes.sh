#!/bin/bash

# Doppler Manager - Error Codes Recovery Playbook
# This file provides structured error codes and recovery instructions for LLM-driven troubleshooting

# Error Code Definitions
declare -A ERROR_CODES=(
    ["E000"]="OK - No error, system is ready"
    ["E001"]="DOPPLER_NOT_INSTALLED - Doppler CLI is not installed"
    ["E002"]="NOT_AUTHENTICATED - Doppler CLI is not logged in"
    ["E003"]="TOKEN_EXPIRED - Doppler token has expired or is invalid"
    ["E004"]="NO_PROJECT_CONFIG - No project/config set for current directory"
    ["E005"]="PERMISSION_DENIED - Insufficient permissions to access secrets"
    ["E006"]="NETWORK_ERROR - Cannot connect to Doppler API"
    ["E007"]="CONFIG_MISMATCH - Project or config setting is invalid"
)

# Recovery Commands
declare -A RECOVERY_COMMANDS=(
    ["E001"]="https://docs.doppler.com/docs/install-cli"
    ["E002"]="doppler login"
    ["E003"]="doppler login"
    ["E004"]="doppler setup"
    ["E005"]="Contact Doppler admin to grant access"
    ["E006"]="Check internet connection and VPN"
    ["E007"]="doppler setup --project <project> --config <config>"
)

# Documentation References
declare -A DOC_REFERENCES=(
    ["E001"]="references/SOP.md#phase-1"
    ["E002"]="references/SOP.md#phase-2"
    ["E003"]="references/SOP.md#phase-2"
    ["E004"]="references/SOP.md#phase-3"
    ["E005"]="references/SOP.md#troubleshooting"
    ["E006"]="references/SOP.md#troubleshooting"
    ["E007"]="references/SOP.md#phase-3"
)

# Get error description
get_error_description() {
    local code="$1"
    echo "${ERROR_CODES[$code]:-UNKNOWN_ERROR}"
}

# Get recovery command
get_recovery_command() {
    local code="$1"
    echo "${RECOVERY_COMMANDS[$code]:-Unknown recovery action}"
}

# Get documentation reference
get_doc_reference() {
    local code="$1"
    echo "${DOC_REFERENCES[$code]:-references/SOP.md}"
}

# Print all error codes (for debugging/validation)
print_error_codes() {
    echo "=== Doppler Manager Error Codes ==="
    for code in "${!ERROR_CODES[@]}"; do
        echo "[$code] ${ERROR_CODES[$code]}"
        echo "  Recovery: ${RECOVERY_COMMANDS[$code]}"
        echo "  Docs: ${DOC_REFERENCES[$code]}"
        echo ""
    done
}

# Export for use by other scripts
export ERROR_CODES
export RECOVERY_COMMANDS
export DOC_REFERENCES

# If called directly, print all error codes
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    print_error_codes
fi