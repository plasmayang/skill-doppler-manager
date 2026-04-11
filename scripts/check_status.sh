#!/bin/bash

# Doppler Manager - Enhanced Status Check
# Outputs structured JSON for LLM parsing with error codes and recovery hints

# Helper function for JSON output (pure bash, no external dependencies)
json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"   # escape backslashes first
    str="${str//\"/\\\"}"   # escape quotes
    str="${str//$'\n'/\\n}" # escape newlines
    str="${str//$'\t'/\\t}" # escape tabs
    str="${str//$'\r'/\\r}" # escape carriage returns
    printf '%s' "\"$str\""
}

# Define error codes
declare -A ERROR_CODES=(
    ["E001"]="DOPPLER_NOT_INSTALLED"
    ["E002"]="NOT_AUTHENTICATED"
    ["E003"]="TOKEN_EXPIRED"
    ["E004"]="NO_PROJECT_CONFIG"
    ["E005"]="PERMISSION_DENIED"
    ["E006"]="NETWORK_ERROR"
    ["E007"]="CONFIG_MISMATCH"
)

# Output JSON status
output_json() {
    local status="$1"
    local code="$2"
    local message="$3"
    local hint="$4"
    local doc="$5"
    local project="${6:-}"
    local config="${7:-}"

    echo "{"
    echo "  \"status\": \"$status\","
    echo "  \"code\": \"$code\","
    echo "  \"message\": $(json_escape "$message"),"
    echo "  \"hint\": $(json_escape "$hint"),"
    echo "  \"documentation\": $(json_escape "$doc"),"

    if [[ -n "$project" ]]; then
        echo "  \"project\": $(json_escape "$project"),"
        echo "  \"config\": $(json_escape "$config")"
    else
        echo "  \"project\": null,"
        echo "  \"config\": null"
    fi
    echo "}"
}

# Ensure Doppler CLI is installed
if ! command -v doppler &> /dev/null; then
    output_json "ERROR" "E001" \
        "Doppler CLI is not installed" \
        "Install Doppler CLI: https://docs.doppler.com/docs/install-cli" \
        "references/SOP.md#phase-1"
    exit 1
fi

# Check configuration and authentication status
# Capture both stdout and stderr to distinguish error types
CONFIGURE_OUTPUT=$(doppler configure 2>&1)
CONFIGURE_EXIT=$?

if [[ $CONFIGURE_EXIT -ne 0 ]]; then
    # Determine specific error type
    if echo "$CONFIGURE_OUTPUT" | grep -qi "expired\|invalid\|unauthorized"; then
        output_json "ERROR" "E003" \
            "Doppler token has expired or is invalid" \
            "Run 'doppler login' to re-authenticate" \
            "references/SOP.md#phase-2"
    elif echo "$CONFIGURE_OUTPUT" | grep -qi "permission\|denied"; then
        output_json "ERROR" "E005" \
            "Permission denied to access Doppler secrets" \
            "Verify your Doppler access token has appropriate permissions" \
            "references/SOP.md#troubleshooting"
    elif echo "$CONFIGURE_OUTPUT" | grep -qi "network\|connection\|timeout"; then
        output_json "ERROR" "E006" \
            "Network error connecting to Doppler" \
            "Check your internet connection and VPN settings" \
            "references/SOP.md#troubleshooting"
    else
        output_json "ERROR" "E002" \
            "Doppler CLI is not authenticated or configured" \
            "Run 'doppler login' to authenticate" \
            "references/SOP.md#phase-2"
    fi
    exit 1
fi

# Extract Project and Config for context
PROJECT=$(doppler configure get project --plain 2>/dev/null)
CONFIG=$(doppler configure get config --plain 2>/dev/null)

# Validate project and config are valid (not placeholder or error values)
if [[ -n "$PROJECT" ]] && [[ -n "$CONFIG" ]]; then
    # Check if the values look like error messages or placeholders
    if echo "$PROJECT" | grep -qiE "^(error|null|none|undefined)$" || \
       echo "$CONFIG" | grep -qiE "^(error|null|none|undefined)$"; then
        output_json "ERROR" "E007" \
            "Config mismatch detected - project or config contains invalid values" \
            "Run 'doppler setup --project <project> --config <config>' to reconfigure" \
            "references/SOP.md#phase-3"
        exit 1
    fi

    # Verify the project/config actually exists by trying to fetch secrets
    VERIFY_OUTPUT=$(doppler secrets get DOPPLER_CONFIG_CHECK --plain 2>&1)
    VERIFY_EXIT=$?

    # If we get an error about missing secret (not an auth error), the config might be wrong
    if [[ $VERIFY_EXIT -ne 0 ]] && echo "$VERIFY_OUTPUT" | grep -qiE "not found|does not exist|invalid"; then
        # This might indicate a config mismatch - but don't fail hard as the secret might just not exist
        :
    fi
fi

if [[ -z "$PROJECT" ]] || [[ -z "$CONFIG" ]]; then
    output_json "WARNING" "E004" \
        "Authenticated, but no default Project or Config is set for this directory" \
        "Run 'doppler setup' to configure project and config for this directory" \
        "references/SOP.md#phase-3"
    exit 0
fi

output_json "OK" "E000" \
    "Authenticated and configured" \
    "Ready to use 'doppler run -- <command>' for secret injection" \
    "references/SOP.md" \
    "$PROJECT" "$CONFIG"
exit 0
