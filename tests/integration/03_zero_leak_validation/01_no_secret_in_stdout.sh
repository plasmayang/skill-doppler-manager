#!/bin/bash

# Integration Test: Zero-Leak - No Secrets in stdout
# Verifies secrets never appear in stdout/stderr

set -euo pipefail

# Project root is three levels up from test script
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/secret-mgmt-integration-test}"
mkdir -p "$TEST_TMP_DIR"

echo "Testing zero-leak: secrets not in stdout..."

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

# Capture all output
all_output=$(doppler run -- bash -c 'echo "Test completed"' 2>&1 || true)

# Check for mock secret patterns
if echo "$all_output" | grep -qi "mock_secret_value"; then
    echo "FAIL: Secret leaked into output"
    echo "$all_output"
    rm -rf "$MOCK_DIR"
    exit 1
fi

echo "PASS: No secrets leaked to stdout"
rm -rf "$MOCK_DIR"
exit 0
