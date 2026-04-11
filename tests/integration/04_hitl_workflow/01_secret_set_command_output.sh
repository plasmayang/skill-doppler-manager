#!/bin/bash

# Integration Test: HITL - Secret Set Command Template
# Verifies the skill outputs a proper command template for HITL

set -euo pipefail

# Project root is three levels up from test script
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/secret-mgmt-integration-test}"
mkdir -p "$TEST_TMP_DIR"

echo "Testing HITL: secret set command template..."

# Setup mock Doppler
MOCK_DIR="/tmp/secret-mgmt-test-mock-$$"
mkdir -p "$MOCK_DIR"

cat << 'EOF' > "$MOCK_DIR/doppler"
#!/bin/bash
case "$1" in
    --version) echo "Doppler 3.10.0 (mock)" ;;
    configure) [[ -z "$2" ]] && exit 0; [[ "$2" == "get" ]] || exit 0
        case "$3" in project) echo "test-project" ;; config) echo "dev" ;; token) echo "dp.st.mock" ;; esac; exit 0 ;;
    secrets) [[ "$2" == "get" ]] && echo "mock_secret_value"; exit 0 ;;
    run) shift 2; eval "$@" ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$MOCK_DIR/doppler"
export PATH="$MOCK_DIR:$PATH"

# Source the manager interface and get the set command template
if [[ -f "$PROJECT_ROOT/scripts/managers/doppler.sh" ]]; then
    source "$PROJECT_ROOT/scripts/managers/doppler.sh"

    # Get the set template
    output=$(sm_set "MY_TEST_SECRET" 2>&1 || true)

    if ! echo "$output" | grep -q "doppler secrets set"; then
        echo "FAIL: No doppler secrets set command in output"
        rm -rf "$MOCK_DIR"
        exit 1
    fi

    # Check that the placeholder <value> is used (not an actual secret value)
    if echo "$output" | grep -q "<value>"; then
        # Good - uses placeholder
        :
    elif echo "$output" | grep -qiE "(sk_|api_key|secret|password|token).*="; then
        echo "FAIL: Secret pattern appeared in command template"
        rm -rf "$MOCK_DIR"
        exit 1
    fi

    echo "PASS: HITL command template is correct"
    echo "$output"
    rm -rf "$MOCK_DIR"
    exit 0
else
    echo "SKIP: Manager implementation not found"
    rm -rf "$MOCK_DIR"
    exit 0
fi
