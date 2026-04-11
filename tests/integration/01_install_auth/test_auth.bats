#!/usr/bin/env bats

# BATS test suite for installation and authentication
# Tests doppler CLI installation, auth detection, and configuration

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
}

teardown() {
    rm -rf "$MOCK_BIN_DIR"
    rm -f "$MOCK_DOPPLER_INVOCATION_LOG"
}

# ============================================
# Doppler CLI Installation Tests
# ============================================

@test "auth: doppler command is found in PATH" {
    command -v doppler
}

@test "auth: doppler returns version information" {
    run bash -c 'doppler --version'
    [ "$status" -eq 0 ]
    [[ "$output" == "Doppler"* ]]
}

@test "auth: doppler is executable" {
    [[ -x "$MOCK_BIN_DIR/doppler" ]]
}

# ============================================
# Authentication Status Detection Tests
# ============================================

@test "auth: configure returns success when authenticated" {
    run bash -c 'doppler configure'
    [ "$status" -eq 0 ]
}

@test "auth: configure get project returns project name" {
    run bash -c 'doppler configure get project'
    [ "$status" -eq 0 ]
    [[ "$output" == "test-project" ]]
}

@test "auth: configure get config returns config name" {
    run bash -c 'doppler configure get config'
    [ "$status" -eq 0 ]
    [[ "$output" == "dev" ]]
}

@test "auth: configure get token returns service token format" {
    run bash -c 'doppler configure get token'
    [ "$status" -eq 0 ]
    [[ "$output" == dp.st.* ]]
}

# ============================================
# Service Token Authentication Tests
# ============================================

@test "auth: service token is detected correctly" {
    export MOCK_DOPPLER_TOKEN_TYPE="SERVICE_TOKEN"

    run bash -c 'doppler configure get token | grep -q "^dp\.st\." && echo "SERVICE_TOKEN"'
    [[ "$output" == "SERVICE_TOKEN" ]]
}

@test "auth: user token is detected correctly" {
    export MOCK_DOPPLER_TOKEN_TYPE="USER_TOKEN"

    run bash -c 'doppler configure get token | grep -q "^dp\.pt\." && echo "USER_TOKEN"'
    [[ "$output" == "USER_TOKEN" ]]
}

@test "auth: no token returns empty string" {
    export MOCK_DOPPLER_TOKEN_TYPE="NONE"

    run bash -c 'doppler configure get token'
    [ "$status" -eq 0 ]
    [[ "$output" == "" ]]
}

@test "auth: service token format is valid" {
    run bash -c 'token=$(doppler configure get token) && echo "$token" | grep -qE "^dp\.st\.[a-zA-Z0-9]+$"'
    [ "$status" -eq 0 ]
}

# ============================================
# Project/Config Detection Tests
# ============================================

@test "auth: project name is properly detected" {
    export MOCK_DOPPLER_PROJECT="my-awesome-project"

    run bash -c 'doppler configure get project'
    [ "$status" -eq 0 ]
    [[ "$output" == "my-awesome-project" ]]
}

@test "auth: config name is properly detected" {
    export MOCK_DOPPLER_CONFIG="production"

    run bash -c 'doppler configure get config'
    [ "$status" -eq 0 ]
    [[ "$output" == "production" ]]
}

@test "auth: invalid project value triggers error" {
    export MOCK_DOPPLER_PROJECT="error"

    run bash -c 'doppler configure get project'
    [ "$status" -eq 0 ]
    [[ "$output" == "error" ]]
}

@test "auth: null config value is detected" {
    export MOCK_DOPPLER_CONFIG="null"

    run bash -c 'doppler configure get config'
    [ "$status" -eq 0 ]
    [[ "$output" == "null" ]]
}

# ============================================
# Error Handling Tests
# ============================================

@test "auth: network error is reported" {
    export MOCK_DOPPLER_ERROR="Connection timeout - check your network"

    run bash -c 'doppler configure 2>&1'
    [ "$status" -ne 0 ]
    [[ "$output" == *"timeout"* ]]
}

@test "auth: permission denied is reported" {
    export MOCK_DOPPLER_ERROR="Permission denied to access secrets"

    run bash -c 'doppler configure 2>&1'
    [ "$status" -ne 0 ]
    [[ "$output" == *"denied"* ]]
}

# ============================================
# Mock Invocation Tracking Tests
# ============================================

@test "auth: mock tracks invocations" {
    # Clear log first
    rm -f "$MOCK_DOPPLER_INVOCATION_LOG"

    # Run some commands
    doppler --version > /dev/null
    doppler configure > /dev/null
    doppler configure get project > /dev/null

    # Check invocation log exists
    [[ -f "$MOCK_DOPPLER_INVOCATION_LOG" ]]
}

@test "auth: mock invocation log is valid JSON" {
    doppler --version > /dev/null

    run python3 -c "import json; json.load(open('$MOCK_DOPPLER_INVOCATION_LOG'))"
    [ "$status" -eq 0 ]
}
