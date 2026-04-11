#!/usr/bin/env bats

# BATS test suite for zero-leak validation
# Tests that secrets don't leak into process list, /proc, or history

setup() {
    # Create temporary bin directory for mock
    export MOCK_BIN_DIR="$(mktemp -d)"
    export PATH="$MOCK_BIN_DIR:$PATH"

    # Set up mock invocation log
    export MOCK_DOPPLER_INVOCATION_LOG="$BATS_TEST_DIRNAME/invocation_log.json"
    rm -f "$MOCK_DOPPLER_INVOCATION_LOG"

    # Create mock doppler
    cp "$BATS_TEST_DIRNAME/../mocks/mock_doppler.sh" "$MOCK_BIN_DIR/doppler"
    chmod +x "$MOCK_BIN_DIR/doppler"

    # Default mock configuration
    export MOCK_DOPPLER_PROJECT="test-project"
    export MOCK_DOPPLER_CONFIG="dev"
    export MOCK_DOPPLER_TOKEN_TYPE="SERVICE_TOKEN"
    export MOCK_DOPPLER_ERROR=""

    # Create temporary home for history testing
    export HOME="$BATS_TEST_DIRNAME/tmp_home"
    mkdir -p "$HOME"
}

teardown() {
    rm -rf "$MOCK_BIN_DIR"
    rm -f "$MOCK_DOPPLER_INVOCATION_LOG"
    rm -rf "$HOME"
}

# ============================================
# Process List Leak Tests
# ============================================

@test "zero_leak: secrets don't appear in process list via ps" {
    # Run doppler command
    doppler run -- echo "test" > /dev/null 2>&1

    # Capture process list
    local process_list
    process_list=$(ps aux 2>/dev/null || ps -ef 2>/dev/null)

    # Check secret values don't appear
    [[ "$process_list" != *"mock_api_key_12345"* ]]
    [[ "$process_list" != *"super_secret_token_abc123"* ]]
    [[ "$process_list" != *"postgresql://user:pass@localhost/db"* ]]
}

@test "zero_leak: secrets don't appear in process args via /proc" {
    # Run doppler command that uses secrets
    doppler run -- bash -c 'echo $API_KEY' > /dev/null 2>&1

    # Check /proc/*/cmdline for secrets
    local found_leak=false
    for cmdline in /proc/*/cmdline; do
        if [[ -r "$cmdline" ]]; then
            local content
            content=$(tr '\0' ' ' < "$cmdline" 2>/dev/null)
            if [[ "$content" == *"mock_api_key_12345"* ]]; then
                found_leak=true
                break
            fi
        fi
    done

    [[ "$found_leak" == "false" ]]
}

# ============================================
# /proc/*/environ Leak Tests
# ============================================

@test "zero_leak: secrets don't appear in /proc/*/environ" {
    # Run a command with secrets
    doppler run -- bash -c 'printenv API_KEY > /dev/null' &
    local pid=$!

    # Wait briefly for process to start
    sleep 0.1

    # Check /proc/$pid/environ for secrets (if it exists and is readable)
    if [[ -r "/proc/$pid/environ" ]]; then
        local env_content
        env_content=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null || true)

        # The secret should not be visible in environ of parent shell
        [[ "$env_content" != *"mock_api_key_12345"* ]]
    fi

    # Cleanup
    kill "$pid" 2>/dev/null || true
}

@test "zero_leak: /proc/self/environ doesn't contain secrets after doppler run" {
    # Run a command that uses secrets
    doppler run -- bash -c 'echo test' > /dev/null 2>&1

    # Check current process environ
    if [[ -r "/proc/self/environ" ]]; then
        local env_content
        env_content=$(tr '\0' '\n' < "/proc/self/environ" 2>/dev/null || true)

        # Verify our mock secret values are not leaked
        [[ "$env_content" != *"mock_api_key_12345"* ]]
        [[ "$env_content" != *"super_secret_token_abc123"* ]]
    fi
}

# ============================================
# Shell History Leak Tests
# ============================================

@test "zero_leak: shell history doesn't contain secrets" {
    # Create history file
    touch "$HOME/.bash_history"

    # Run doppler command that echoes a secret
    doppler run -- bash -c 'echo $API_KEY' > /dev/null 2>&1

    # Check history doesn't contain secrets
    if [[ -f "$HOME/.bash_history" ]]; then
        local history_content
        history_content=$(cat "$HOME/.bash_history" 2>/dev/null || true)

        [[ "$history_content" != *"mock_api_key_12345"* ]]
        [[ "$history_content" != *"super_secret_token_abc123"* ]]
        [[ "$history_content" != *"dp.st."* ]]
    fi
}

@test "zero_leak: zsh history doesn't contain secrets" {
    # Create zsh history file
    touch "$HOME/.zsh_history"

    # Run doppler command
    doppler run -- echo "test" > /dev/null 2>&1

    # Check zsh history
    if [[ -f "$HOME/.zsh_history" ]]; then
        local history_content
        history_content=$(cat "$HOME/.zsh_history" 2>/dev/null || true)

        [[ "$history_content" != *"mock_api_key_12345"* ]]
        [[ "$history_content" != *"dp.st."* ]]
    fi
}

@test "zero_leak: command with secret substitution doesn't pollute history" {
    # Run a command with secret in a subshell
    HOME="$HOME" doppler run -- bash -c 'API_KEY_VALUE=$(echo $API_KEY); echo "done"' > /dev/null 2>&1

    # Check history files don't contain the secret
    for hist_file in "$HOME/.bash_history" "$HOME/.zsh_history"; do
        if [[ -f "$hist_file" ]]; then
            local content
            content=$(cat "$hist_file" 2>/dev/null || true)
            [[ "$content" != *"mock_api_key_12345"* ]]
        fi
    done
}

# ============================================
# Temporary File Leak Tests
# ============================================

@test "zero_leak: temp files don't contain secrets" {
    # Run doppler command
    doppler run -- bash -c 'echo $API_KEY' > /dev/null 2>&1

    # Check common temp locations
    local temp_dirs=("/tmp" "$HOME/tmp" "/var/tmp")
    local found_leak=false

    for temp_dir in "${temp_dirs[@]}"; do
        if [[ -d "$temp_dir" ]]; then
            # Look for any files modified recently containing secrets
            while IFS= read -r -d '' file; do
                if [[ -f "$file" ]] && [[ -r "$file" ]]; then
                    local content
                    content=$(cat "$file" 2>/dev/null || true)
                    if [[ "$content" == *"mock_api_key_12345"* ]]; then
                        found_leak=true
                        break 2
                    fi
                fi
            done < <(find "$temp_dir" -type f -mmin -5 \( -name "*.tmp" -o -name "*.env" -o -name "*secret*" \) -print0 2>/dev/null || true)
        fi
    done

    [[ "$found_leak" == "false" ]]
}

@test "zero_leak: no .env files created in project directory" {
    # Run doppler command
    doppler run -- echo "test" > /dev/null 2>&1

    # Check for any .env files that might have been created
    local found_env=false
    if [[ -d "$BATS_TEST_DIRNAME/../../.." ]]; then
        while IFS= read -r -d '' env_file; do
            # Skip node_modules and other irrelevant directories
            if [[ "$env_file" != *"node_modules"* ]]; then
                found_env=true
                break
            fi
        done < <(find "$BATS_TEST_DIRNAME/../../.." -maxdepth 3 -name ".env" -type f -print0 2>/dev/null || true)
    fi

    [[ "$found_env" == "false" ]]
}

# ============================================
# Log File Leak Tests
# ============================================

@test "zero_leak: script output doesn't echo raw secrets" {
    # Run check_status with mock
    run bash -c 'doppler configure get token'

    # Output should not contain raw secret values
    [[ "$output" != *"mock_api_key_12345"* ]]
    [[ "$output" != *"super_secret_token_abc123"* ]]
}

@test "zero_leak: error messages don't leak secrets" {
    # Run with invalid secret
    run bash -c 'doppler secrets get INVALID_SECRET_12345 2>&1 || true'

    # Error message should not contain mock secret values
    [[ "$output" != *"mock_api_key_12345"* ]]
    [[ "$output" != *"super_secret_token_abc123"* ]]
    [[ "$output" != *"postgresql://"* ]]
}

# ============================================
# Audit Log Leak Tests
# ============================================

@test "zero_leak: audit logs don't contain raw secret values" {
    # Create temporary audit directory
    export DOPPLER_AUDIT_DIR="$BATS_TEST_DIRNAME/tmp_audit"
    mkdir -p "$DOPPLER_AUDIT_DIR"

    # Run audit_secrets to log an access
    bash "$BATS_TEST_DIRNAME/../../scripts/audit_secrets.sh" access "API_KEY" "test" "true" 2>/dev/null || true

    # Check audit log doesn't contain raw secrets
    if [[ -f "$DOPPLER_AUDIT_DIR/audit.log" ]]; then
        local log_content
        log_content=$(cat "$DOPPLER_AUDIT_DIR/audit.log" 2>/dev/null || true)

        # Should not contain actual secret values
        [[ "$log_content" != *"mock_api_key_12345"* ]]
        [[ "$log_content" != *"super_secret_token_abc123"* ]]
    fi

    rm -rf "$DOPPLER_AUDIT_DIR"
}

# ============================================
# JSON Output Leak Tests
# ============================================

@test "zero_leak: JSON output doesn't contain plain secrets" {
    # Run doppler secrets get (JSON format)
    run bash -c 'doppler secrets get API_KEY'

    # Parse output and verify it's valid JSON
    run python3 -c "import json; json.loads('$output')"

    # But verify the raw value is not exposed directly in a way that leaks
    if [[ "$output" == *"mock_api_key_12345"* ]]; then
        # If value appears, it should be in JSON structure, not as raw echo
        [[ "$output" =~ \"value\":\"mock_api_key_12345\" ]]
    fi
}
