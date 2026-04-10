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
    [[ "$output" == *"STATUS: ERROR - Doppler CLI is not installed."* ]]
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
    [[ "$output" == *"STATUS: ERROR - Doppler CLI is installed but not authenticated or configured."* ]]
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
    [[ "$output" == *"STATUS: WARNING - Authenticated, but no default Project or Config is set for this directory."* ]]
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
    [[ "$output" == *"STATUS: OK - Authenticated (Project: keys4_token-providers, Config: stg)"* ]]
}
