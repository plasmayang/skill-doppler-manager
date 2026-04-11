#!/bin/bash

# Mock Doppler CLI for integration testing
# Tracks invocations and returns realistic JSON output

# Store secrets for testing
declare -A MOCK_SECRETS=(
    ["API_KEY"]="mock_api_key_12345"
    ["DATABASE_URL"]="postgresql://user:pass@localhost/db"
    ["SECRET_TOKEN"]="super_secret_token_abc123"
    ["JWT_SECRET"]="jwt_secret_key_xyz789"
    ["AWS_ACCESS_KEY"]="AKIA_MOCK_ACCESS_KEY"
    ["STRIPE_KEY"]="sk_test_mock_stripe_key"
)

# Token type for authentication tests
MOCK_TOKEN_TYPE="${MOCK_DOPPLER_TOKEN_TYPE:-SERVICE_TOKEN}"

# Project/config settings
MOCK_PROJECT="${MOCK_DOPPLER_PROJECT:-test-project}"
MOCK_CONFIG="${MOCK_DOPPLER_CONFIG:-dev}"

# Error simulation
MOCK_ERROR="${MOCK_DOPPLER_ERROR:-}"

# Invocation log file
INVOCATION_LOG="${MOCK_DOPPLER_INVOCATION_LOG:-/tmp/mock_doppler_invocations.json}"

# Initialize invocation log
init_mock_log() {
    echo "[]" > "$INVOCATION_LOG"
}

# Log an invocation
log_invocation() {
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Read existing log
    local log_content
    log_content=$(cat "$INVOCATION_LOG" 2>/dev/null || echo "[]")

    # Create new entry
    local args_json="[]"
    if [[ $# -gt 0 ]]; then
        args_json=$(printf '%s\n' "$@" | python3 -c "import json,sys; print(json.dumps([l.strip() for l in sys.stdin]))" 2>/dev/null || echo "[]")
    fi

    local new_entry
    new_entry=$(python3 -c "
import json
import sys
log = json.loads('''$log_content''')
log.append({
    'timestamp': '$timestamp',
    'command': 'doppler $*',
    'args': $args_json
})
print(json.dumps(log, indent=2))
" 2>/dev/null || echo "[]")

    echo "$log_content" > "$INVOCATION_LOG"
}

# Handle --version
handle_version() {
    echo "Doppler 3.10.0"
    exit 0
}

# Handle configure command
handle_configure() {
    # Simulate error if MOCK_DOPPLER_ERROR is set
    if [[ -n "$MOCK_ERROR" ]]; then
        echo "$MOCK_ERROR" >&2
        exit 1
    fi

    # Handle: doppler configure (check auth status)
    if [[ $# -eq 0 ]]; then
        exit 0
    fi

    # Handle: doppler configure get project
    if [[ "$1" == "get" && "$2" == "project" ]]; then
        echo "$MOCK_PROJECT"
        exit 0
    fi

    # Handle: doppler configure get config
    if [[ "$1" == "get" && "$2" == "config" ]]; then
        echo "$MOCK_CONFIG"
        exit 0
    fi

    # Handle: doppler configure get token
    if [[ "$1" == "get" && "$2" == "token" ]]; then
        case "$MOCK_TOKEN_TYPE" in
            SERVICE_TOKEN)
                echo "dp.st.mock_service_token_abc123xyz"
                ;;
            USER_TOKEN)
                echo "dp.pt.mock_user_token_abc123xyz"
                ;;
            NONE)
                echo ""
                ;;
            *)
                echo ""
                ;;
        esac
        exit 0
    fi

    exit 0
}

# Handle secrets get
handle_secret_get() {
    local secret_name="$1"
    shift

    # Handle --plain flag
    local plain=false
    for arg in "$@"; do
        if [[ "$arg" == "--plain" ]]; then
            plain=true
        fi
    done

    if [[ -z "$secret_name" ]]; then
        echo "ERROR: secret name required" >&2
        exit 1
    fi

    # Simulate error if MOCK_DOPPLER_ERROR is set
    if [[ -n "$MOCK_ERROR" ]]; then
        echo "$MOCK_ERROR" >&2
        exit 1
    fi

    # Check if secret exists
    if [[ -z "${MOCK_SECRETS[$secret_name]:-}" ]]; then
        echo "Error: Secret '$secret_name' not found" >&2
        exit 1
    fi

    local value="${MOCK_SECRETS[$secret_name]}"

    if [[ "$plain" == "true" ]]; then
        echo "$value"
    else
        # Return JSON format
        cat <<EOF
{
  "name": "$secret_name",
  "value": "$value",
  "computed": false
}
EOF
    fi

    exit 0
}

# Handle run command (doppler run -- echo $SECRET)
handle_run() {
    shift  # Skip 'run'

    # Handle: doppler run -- echo $SECRET
    if [[ "$1" == "--" ]]; then
        shift
        # Execute the command with secrets injected via environment
        # In real Doppler, secrets are injected as environment variables
        # For mock purposes, we just execute the command

        # Simulate secret injection by setting environment variables
        for secret_name in "${!MOCK_SECRETS[@]}"; do
            export "$secret_name=${MOCK_SECRETS[$secret_name]}"
        done

        # Execute the remaining command
        "$@"
        exit $?
    fi

    # Handle: doppler run (no command, just injection check)
    if [[ $# -eq 0 ]]; then
        exit 0
    fi

    exit 0
}

# Initialize log on first call
init_mock_log

# Main entry - log the invocation and dispatch
log_invocation "$@"

# Dispatch based on first argument
case "$1" in
    --version)
        handle_version
        ;;
    configure)
        shift
        handle_configure "$@"
        ;;
    secrets)
        if [[ "$2" == "get" ]]; then
            handle_secret_get "$3" "${@:4}"
        else
            exit 0
        fi
        ;;
    run)
        handle_run "$@"
        ;;
    *)
        exit 0
        ;;
esac
