setup() {
    # Create a temporary bin directory to mock the doppler binary
    export MOCK_BIN_DIR="$(mktemp -d)"
    export PATH="$MOCK_BIN_DIR:$PATH"
}

teardown() {
    rm -rf "$MOCK_BIN_DIR"
}

@test "check_status: fails when doppler is not installed" {
    # Do not create a mock doppler binary, ensuring it's not found
    run bash ./scripts/check_status.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *'"status": "ERROR"'* ]]
    [[ "$output" == *'"code": "E001"'* ]]
    [[ "$output" == *'Doppler CLI is not installed'* ]]
}

@test "check_status: fails when doppler is installed but not configured" {
    # Create a mock doppler binary that fails on 'configure'
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
if [[ "$1" == "configure" ]]; then
    exit 1
fi
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    run bash ./scripts/check_status.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *'"status": "ERROR"'* ]]
    [[ "$output" == *'"code": "E002"'* ]]
    [[ "$output" == *'not authenticated or configured'* ]]
}

@test "check_status: fails when token is expired" {
    # Create a mock doppler binary that reports expired token
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
if [[ "$1" == "configure" ]]; then
    echo "Token has expired. Please run 'doppler login' again." >&2
    exit 1
fi
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    run bash ./scripts/check_status.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *'"status": "ERROR"'* ]]
    [[ "$output" == *'"code": "E003"'* ]]
    [[ "$output" == *'expired'* ]]
}

@test "check_status: warns when authenticated but missing project or config" {
    # Create a mock doppler binary that succeeds on 'configure' but returns empty for 'get project/config'
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
if [[ "$1" == "configure" && -z "$2" ]]; then
    exit 0
elif [[ "$1" == "configure" && "$2" == "get" ]]; then
    exit 0
fi
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    run bash ./scripts/check_status.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status": "WARNING"'* ]]
    [[ "$output" == *'"code": "E004"'* ]]
    [[ "$output" == *'no default Project or Config'* ]]
}

@test "check_status: succeeds when fully authenticated with project and config" {
    # Create a mock doppler binary that returns successful configuration details
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
if [[ "$1" == "configure" && -z "$2" ]]; then
    exit 0
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "project" ]]; then
    echo "keys4_token-providers"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "config" ]]; then
    echo "stg"
fi
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    run bash ./scripts/check_status.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status": "OK"'* ]]
    [[ "$output" == *'"code": "E000"'* ]]
    [[ "$output" == *'"project": "keys4_token-providers"'* ]]
    [[ "$output" == *'"config": "stg"'* ]]
}

@test "check_status: fails with permission denied" {
    # Create a mock doppler binary that reports permission denied
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
if [[ "$1" == "configure" ]]; then
    echo "Permission denied to access secrets." >&2
    exit 1
fi
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    run bash ./scripts/check_status.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *'"status": "ERROR"'* ]]
    [[ "$output" == *'"code": "E005"'* ]]
    [[ "$output" == *'Permission denied'* ]]
}

@test "check_status: fails with network error" {
    # Create a mock doppler binary that reports network error
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
if [[ "$1" == "configure" ]]; then
    echo "Connection timeout - check your network" >&2
    exit 1
fi
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    run bash ./scripts/check_status.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *'"status": "ERROR"'* ]]
    [[ "$output" == *'"code": "E006"'* ]]
    [[ "$output" == *'Network error'* ]]
}

@test "check_status: fails with E007 config mismatch for invalid project" {
    # Create a mock doppler binary that returns invalid project value
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
if [[ "$1" == "configure" && -z "$2" ]]; then
    exit 0
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "project" ]]; then
    echo "error"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "config" ]]; then
    echo "prd"
fi
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    run bash ./scripts/check_status.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *'"status": "ERROR"'* ]]
    [[ "$output" == *'"code": "E007"'* ]]
    [[ "$output" == *'Config mismatch'* ]]
}

@test "check_status: fails with E007 config mismatch for invalid config" {
    # Create a mock doppler binary that returns invalid config value
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
if [[ "$1" == "configure" && -z "$2" ]]; then
    exit 0
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "project" ]]; then
    echo "my-project"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "config" ]]; then
    echo "null"
fi
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    run bash ./scripts/check_status.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *'"status": "ERROR"'* ]]
    [[ "$output" == *'"code": "E007"'* ]]
}

@test "check_status: output is valid JSON" {
    # Create a mock doppler binary that returns valid configuration
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
if [[ "$1" == "configure" && -z "$2" ]]; then
    exit 0
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "project" ]]; then
    echo "test-project"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "config" ]]; then
    echo "dev"
fi
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    run bash ./scripts/check_status.sh

    # Verify output is valid JSON by parsing it
    echo "$output" | python3 -c "import json,sys; json.load(sys.stdin); print('valid')"
    [ "$status" -eq 0 ]
}
