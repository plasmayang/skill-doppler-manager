#!/usr/bin/env bats

# BATS test suite for leak prevention (Adversarial Testing)
# Tests that verify the zero-leak architecture holds under attack

setup() {
    export MOCK_BIN_DIR="$(mktemp -d)"
    export PATH="$MOCK_BIN_DIR:$PATH"
    export HOME="$BATS_TEST_DIRNAME/../tests/tmp_home_leak"
    mkdir -p "$HOME"
}

teardown() {
    rm -rf "$MOCK_BIN_DIR"
    rm -rf "$HOME"
}

# Create a mock doppler that would leak if used improperly
create_leaky_doppler() {
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
# This mock simulates a secret manager
# It should NEVER output secret values to stdout/stderr
if [[ "$1" == "--version" ]]; then
    echo "Doppler 3.10.0"
elif [[ "$1" == "configure" ]]; then
    exit 0
elif [[ "$1" == "secrets" && "$2" == "get" ]]; then
    # WRONG: This would leak the secret if echo is used
    echo "SUPER_SECRET_API_KEY=actual_secret_value_12345"
    exit 0
elif [[ "$1" == "secrets" && "$2" == "--quiet" ]]; then
    echo "API_KEY=secret"
fi
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"
}

@test "leak_attempts: script never echoes raw secrets" {
    create_leaky_doppler

    # Run check_status which should NOT leak secrets
    run bash ./scripts/check_status.sh

    # Output should NOT contain secret values
    [[ "$output" != *"actual_secret_value_12345"* ]]
    [[ "$output" != *"SUPER_SECRET_API_KEY"* ]]
    [[ "$output" != *"secret_value"* ]]
}

@test "leak_attempts: audit_secrets never logs secret values" {
    # Create mock doppler
    create_leaky_doppler

    # Run audit_secrets access command
    run bash ./scripts/audit_secrets.sh access "TEST_SECRET"

    # Log file should NOT contain the actual secret value
    if [ -f "./audit_log.jsonl" ]; then
        LOG_CONTENT=$(cat "./audit_log.jsonl")
        [[ "$LOG_CONTENT" != *"actual_secret_value_12345"* ]]
    fi
}

@test "leak_attempts: verify_environment never prints secret values" {
    create_leaky_doppler

    run bash ./scripts/verify_environment.sh

    # Output should NOT contain secret values
    [[ "$output" != *"actual_secret_value_12345"* ]]
    [[ "$output" != *"SUPER_SECRET_API_KEY"* ]]
    [[ "$output" != *"secret_value"* ]]
}

@test "leak_attempts: emergency_seal sanitizes all output" {
    create_leaky_doppler

    # Run emergency seal
    run bash ./scripts/emergency_seal.sh "test-incident"

    # Incident report should NOT contain raw secrets
    INCIDENT_FILE=$(find . -name "incident_*" -type f 2>/dev/null | head -1)
    if [ -n "$INCIDENT_FILE" ]; then
        CONTENT=$(cat "$INCIDENT_FILE")
        [[ "$CONTENT" != *"actual_secret_value_12345"* ]]
        [[ "$CONTENT" != *"SUPER_SECRET_API_KEY"* ]]
    fi
}

@test "leak_attempts: secret_manager_interface never echoes secrets" {
    # Source the interface
    run bash -c 'source ./scripts/secret_manager_interface.sh && sm_load doppler && sm_status'

    # Status output should NOT contain secret values
    [[ "$output" != *"actual_secret_value_12345"* ]]
    [[ "$output" != *"SUPER_SECRET"* ]]
}

@test "leak_attempts: detect_manager sanitizes all manager output" {
    run bash ./scripts/detect_manager.sh

    # Output should NOT contain secret values from any manager
    [[ "$output" != *"actual_secret"* ]]
    [[ "$output" != *"secret_value"* ]]
    [[ "$output" != *"API_KEY"* ]]
}

@test "leak_attempts: bash history remains clean after operations" {
    create_leaky_doppler

    # Run some operations
    bash ./scripts/check_status.sh > /dev/null 2>&1 || true
    bash ./scripts/detect_manager.sh > /dev/null 2>&1 || true

    # History file should NOT contain secrets
    if [ -f "$HOME/.bash_history" ]; then
        HIST_CONTENT=$(cat "$HOME/.bash_history")
        [[ "$HIST_CONTENT" != *"actual_secret_value_12345"* ]]
        [[ "$HIST_CONTENT" != *"SUPER_SECRET"* ]]
    fi
}

@test "leak_attempts: JSON output never contains plain secrets" {
    create_leaky_doppler

    run bash ./scripts/check_status.sh

    # Parse as JSON (if valid) and check values are not raw secrets
    # The JSON should have sanitized values or references, not actual secrets
    if [[ "$output" == *"{"* ]] && [[ "$output" == *"}"* ]]; then
        # If it looks like JSON, ensure no raw secret values
        [[ "$output" != *"?value":"actual"* ]]
        [[ "$output" != *":\"secret_value"* ]]
    fi
}

@test "leak_attempts: error messages never leak secrets" {
    create_leaky_doppler

    # Run with invalid config to trigger error path
    run bash ./scripts/check_status.sh

    # Error messages should NOT contain secret values
    [[ "$output" != *"actual_secret_value_12345"* ]]
    [[ "$output" != *"SUPER_SECRET"* ]]
    [[ "$output" != *"_KEY="* ]]
    [[ "$output" != *"_SECRET="* ]]
}

@test "leak_attempts: HITL commands never include secret values" {
    # The sm_set function should output a command template, NOT the actual value
    run bash -c 'source ./scripts/secret_manager_interface.sh && sm_load doppler && sm_set TEST_SECRET'

    # Output should be a command template, not a command with the actual value
    [[ "$output" != *"actual_secret"* ]]
    [[ "$output" != *"secret_value"* ]]
    # Should contain something like "doppler secrets set" command template
    [[ "$output" == *"doppler"* ]] || [[ "$output" == *"set"* ]]
}
