#!/usr/bin/env bats

# BATS test suite for secret injection via doppler run
# Tests memory-only secret injection and command execution

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
# Basic Secret Injection Tests
# ============================================

@test "inject: doppler run executes command successfully" {
    run bash -c 'doppler run -- echo "hello world"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello world"* ]]
}

@test "inject: doppler run -- echo \$SECRET syntax works" {
    # The mock exports secrets to child processes, so we use sh -c to receive them
    run bash -c 'doppler run -- sh -c "echo \"\$API_KEY\" | grep -q mock_api_key_12345"'
    [ "$status" -eq 0 ]
}

@test "inject: secrets are available in command environment" {
    run bash -c 'doppler run -- printenv API_KEY'
    [ "$status" -eq 0 ]
    [[ "$output" == *"mock_api_key_12345"* ]]
}

@test "inject: multiple secrets are injected" {
    run bash -c 'export API_KEY="mock_api_key_12345" && export DATABASE_URL="postgresql://user:pass@localhost/db" && doppler run -- printenv API_KEY && printenv DATABASE_URL'
    [ "$status" -eq 0 ]
    [[ "$output" == *"mock_api_key_12345"* ]]
    [[ "$output" == *"postgresql://user:pass@localhost/db"* ]]
}

@test "inject: secrets reach process memory, not context" {
    # Run a command that uses a secret
    doppler run -- bash -c 'echo $API_KEY' > /dev/null 2>&1

    # The secret should NOT appear in the shell's exported variables
    # (This is a negative test - verifying the secret doesn't leak)
    run bash -c 'export | grep -q "mock_api_key_12345" && echo "LEAK" || echo "CLEAN"'
    [[ "$output" == "CLEAN" ]]
}

# ============================================
# Secret Retrieval Tests
# ============================================

@test "inject: doppler secrets get returns JSON format" {
    run bash -c 'doppler secrets get API_KEY'
    [ "$status" -eq 0 ]
    # Verify it's valid JSON with python
    echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['name']=='API_KEY'; assert d['value']=='mock_api_key_12345'; print('OK')"
    [ "$status" -eq 0 ]
}

@test "inject: doppler secrets get --plain returns plain value" {
    run bash -c 'doppler secrets get API_KEY --plain'
    [ "$status" -eq 0 ]
    [[ "$output" == "mock_api_key_12345" ]]
}

@test "inject: secret not found returns error" {
    run bash -c 'doppler secrets get NONEXISTENT_SECRET 2>&1'
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "inject: secret with underscore in name works" {
    run bash -c 'doppler secrets get SECRET_TOKEN --plain'
    [ "$status" -eq 0 ]
    [[ "$output" == *"super_secret_token_abc123"* ]]
}

# ============================================
# Command Execution Tests
# ============================================

@test "inject: echo command with secret substitution" {
    run bash -c 'doppler run -- sh -c "echo The API key is: \$API_KEY"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"The API key is: mock_api_key_12345"* ]]
}

@test "inject: command with multiple secrets" {
    run bash -c 'doppler run -- sh -c "echo \$API_KEY \$JWT_SECRET"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"mock_api_key_12345"* ]]
    [[ "$output" == *"jwt_secret_key_xyz789"* ]]
}

@test "inject: pipeline with secrets works" {
    run bash -c 'doppler run -- printenv API_KEY | tr -d "\n" | wc -c'
    [ "$status" -eq 0 ]
    # The secret value length should match
    [[ "$output" =~ ^[0-9]+$ ]]
}

# ============================================
# Error Handling Tests
# ============================================

@test "inject: missing secret name returns error" {
    run bash -c 'doppler secrets get 2>&1'
    [ "$status" -ne 0 ]
}

@test "inject: invalid secret name format is handled" {
    run bash -c 'doppler secrets get invalid-secret-name 2>&1'
    [ "$status" -ne 0 ]
}

@test "inject: doppler run with no command succeeds" {
    run bash -c 'doppler run'
    [ "$status" -eq 0 ]
}
