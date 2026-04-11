#!/usr/bin/env bats

# BATS test suite for scripts/verify_environment.sh
# Tests deep environment verification functionality

setup() {
    # Create temporary directory for mocking
    export MOCK_BIN_DIR="$(mktemp -d)"
    export PATH="$MOCK_BIN_DIR:$PATH"
    export HOME="$BATS_TEST_DIRNAME/../tests/tmp_home"
    mkdir -p "$HOME"

    # Create mock history files
    touch "$HOME/.bash_history"
    touch "$HOME/.zsh_history"
}

teardown() {
    rm -rf "$MOCK_BIN_DIR"
    rm -rf "$HOME"
}

SCRIPT="./scripts/verify_environment.sh"

@test "verify_environment: passes when doppler is installed and configured" {
    # Create mock doppler that returns valid configuration
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
# IMPORTANT: More specific conditions MUST come before general ones
if [[ "$1" == "--version" ]]; then
    echo "Doppler 3.10.0"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "token" && "$4" == "--plain" ]]; then
    echo "dp.st.abc123xyz"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "project" && "$4" == "--plain" ]]; then
    echo "my-project"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "config" && "$4" == "--plain" ]]; then
    echo "dev"
elif [[ "$1" == "configure" ]]; then
    exit 0
elif [[ "$1" == "secrets" && "$2" == "--quiet" ]]; then
    echo "SECRET1=value1"
    echo "SECRET2=value2"
fi
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    # Mock curl for network check
    cat << 'EOF' > "$MOCK_BIN_DIR/curl"
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/curl"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Environment verification passed"* ]]
}

@test "verify_environment: fails when doppler is not installed" {
    # Do not create doppler mock - it won't be found

    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Doppler CLI not found"* ]]
    [[ "$output" == *"FAIL"* ]]
}

@test "verify_environment: detects not authenticated state" {
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "Doppler 3.10.0"
elif [[ "$1" == "configure" ]]; then
    exit 1
fi
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Not authenticated"* ]]
    [[ "$output" == *"FAIL"* ]]
}

@test "verify_environment: identifies service token type" {
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "Doppler 3.10.0"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "token" && "$4" == "--plain" ]]; then
    echo "dp.st.abc123xyz"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "project" && "$4" == "--plain" ]]; then
    echo "test-project"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "config" && "$4" == "--plain" ]]; then
    echo "dev"
elif [[ "$1" == "configure" ]]; then
    exit 0
fi
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Service Token"* ]]
}

@test "verify_environment: warns about personal token type" {
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "Doppler 3.10.0"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "token" && "$4" == "--plain" ]]; then
    echo "dp.pt.abc123xyz"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "project" && "$4" == "--plain" ]]; then
    echo "test-project"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "config" && "$4" == "--plain" ]]; then
    echo "dev"
elif [[ "$1" == "configure" ]]; then
    exit 0
fi
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Personal Token"* ]]
    [[ "$output" == *"WARN"* ]]
}

@test "verify_environment: warns about missing project/config" {
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "Doppler 3.10.0"
elif [[ "$1" == "configure" ]]; then
    exit 0
elif [[ "$1" == "configure" && "$2" == "get" && "$4" == "--plain" ]]; then
    echo ""
fi
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No project/config set"* ]]
    [[ "$output" == *"WARN"* ]]
}

@test "verify_environment: detects invalid project name" {
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "Doppler 3.10.0"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "project" && "$4" == "--plain" ]]; then
    echo "error"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "config" && "$4" == "--plain" ]]; then
    echo "dev"
elif [[ "$1" == "configure" ]]; then
    exit 0
fi
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Project name appears invalid"* ]]
}

@test "verify_environment: detects legacy .env files" {
    # Create mock doppler
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    # Create a test project with .env file
    export HOME="$BATS_TEST_DIRNAME/../tests/tmp_home_env"
    mkdir -p "$HOME/project"
    echo "SECRET=value" > "$HOME/project/.env"

    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *".env"* ]]
    [[ "$output" == *"security risk"* ]]
    [[ "$output" == *"WARN"* ]]
}

@test "verify_environment: passes when no .env files exist" {
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "Doppler 3.10.0"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "project" && "$4" == "--plain" ]]; then
    echo "test-project"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "config" && "$4" == "--plain" ]]; then
    echo "dev"
elif [[ "$1" == "configure" ]]; then
    exit 0
fi
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    # Create a clean test directory with no .env
    export HOME="$BATS_TEST_DIRNAME/../tests/tmp_home_clean"
    mkdir -p "$HOME"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No .env files found"* ]]
    [[ "$output" == *"PASS"* ]]
}

@test "verify_environment: checks shell history for secrets" {
    # Create mock doppler
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    # Create history with potential secrets
    echo "export API_KEY=secret123" > "$HOME/.bash_history"

    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"shell history"* ]]
    [[ "$output" == *"WARN"* ]]
}

@test "verify_environment: passes with clean shell history" {
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "Doppler 3.10.0"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "project" && "$4" == "--plain" ]]; then
    echo "test-project"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "config" && "$4" == "--plain" ]]; then
    echo "dev"
elif [[ "$1" == "configure" ]]; then
    exit 0
fi
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    # Create clean history
    echo "ls -la" > "$HOME/.bash_history"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No obvious secrets in shell history"* ]]
}

@test "verify_environment: counts secrets in config" {
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "Doppler 3.10.0"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "project" && "$4" == "--plain" ]]; then
    echo "test-project"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "config" && "$4" == "--plain" ]]; then
    echo "dev"
elif [[ "$1" == "secrets" && "$2" == "--quiet" ]]; then
    echo "SECRET1=value1"
    echo "SECRET2=value2"
    echo "SECRET3=value3"
elif [[ "$1" == "configure" ]]; then
    exit 0
fi
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"3 secrets"* ]]
}

@test "verify_environment: warns when cannot reach Doppler API" {
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "Doppler 3.10.0"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "project" && "$4" == "--plain" ]]; then
    echo "test-project"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "config" && "$4" == "--plain" ]]; then
    echo "dev"
elif [[ "$1" == "configure" ]]; then
    exit 0
fi
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    # Create curl mock that fails
    cat << 'EOF' > "$MOCK_BIN_DIR/curl"
#!/bin/bash
exit 1
EOF
    chmod +x "$MOCK_BIN_DIR/curl"

    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Cannot reach Doppler API"* ]]
    [[ "$output" == *"network"* ]]
}

@test "verify_environment: summary shows issue count" {
    # Create doppler mock that fails configure
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
exit 1
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Found"*"issue"* ]]
    [[ "$output" == *"Verification Summary"* ]]
}

@test "verify_environment: provides check_status reference in failure" {
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
exit 1
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"check_status.sh"* ]]
    [[ "$output" == *"SOP.md"* ]]
}

@test "verify_environment: uses colors in output" {
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "Doppler 3.10.0"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "project" && "$4" == "--plain" ]]; then
    echo "test-project"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "config" && "$4" == "--plain" ]]; then
    echo "dev"
elif [[ "$1" == "configure" ]]; then
    exit 0
fi
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    # Mock curl for network check
    cat << 'EOF' > "$MOCK_BIN_DIR/curl"
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/curl"

    run bash "$SCRIPT"
    # Check for ANSI color codes (look for ESC character which is byte 0x1b)
    [[ "$output" == *$'\033['* ]]
}

@test "verify_environment: shows INFO/PASS/WARN/FAIL indicators" {
    cat << 'EOF' > "$MOCK_BIN_DIR/doppler"
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "Doppler 3.10.0"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "project" && "$4" == "--plain" ]]; then
    echo "test-project"
elif [[ "$1" == "configure" && "$2" == "get" && "$3" == "config" && "$4" == "--plain" ]]; then
    echo "dev"
elif [[ "$1" == "configure" ]]; then
    exit 0
fi
EOF
    chmod +x "$MOCK_BIN_DIR/doppler"

    # Mock curl for network check
    cat << 'EOF' > "$MOCK_BIN_DIR/curl"
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/curl"

    run bash "$SCRIPT"
    [[ "$output" == *"[INFO]"* ]]
    [[ "$output" == *"[PASS]"* ]]
}
