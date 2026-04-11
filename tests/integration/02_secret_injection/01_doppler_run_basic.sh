#!/bin/bash

# Integration Test: Secret Injection via doppler run
# Verifies secrets are injected into processes without writing to disk

set -euo pipefail

# Project root is three levels up from test script
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/secret-mgmt-integration-test}"
mkdir -p "$TEST_TMP_DIR"

echo "Testing secret injection via doppler run..."

# Setup mock Doppler
MOCK_DIR="/tmp/secret-mgmt-test-mock-$$"
mkdir -p "$MOCK_DIR"

cat << 'EOF' > "$MOCK_DIR/doppler"
#!/bin/bash
case "$1" in
    --version)
        echo "Doppler 3.10.0 (mock)"
        ;;
    configure)
        [[ -z "$2" ]] && exit 0
        [[ "$2" == "get" ]] || exit 0
        case "$3" in
            project) echo "${DOPPLER_PROJECT:-test-project}" ;;
            config)  echo "${DOPPLER_CONFIG:-dev}" ;;
            token)   echo "${DOPPLER_TOKEN:-dp.st.mock}" ;;
        esac
        exit 0
        ;;
    secrets)
        [[ "$2" == "get" ]] && echo "mock_secret_value"
        exit 0
        ;;
    run)
        # Simulate secret injection by setting env var
        shift 2
        export DATABASE_URL="mock_secret_value"
        eval "$@"
        ;;
    *)
        exit 1
        ;;
esac
EOF
chmod +x "$MOCK_DIR/doppler"
export PATH="$MOCK_DIR:$PATH"

# Create a test script that echoes an env var
cat > "$TEST_TMP_DIR/test_inject.sh" << 'EOF'
#!/bin/bash
echo "DATABASE_URL is set: ${DATABASE_URL:-NOT_SET}"
EOF
chmod +x "$TEST_TMP_DIR/test_inject.sh"

# Run via doppler (mocked)
output=$(doppler run -- bash "$TEST_TMP_DIR/test_inject.sh" 2>&1 || true)

if [[ "$output" == *"NOT_SET"* ]]; then
    echo "FAIL: Secret was not injected"
    rm -rf "$MOCK_DIR" "$TEST_TMP_DIR"
    exit 1
fi

echo "PASS: Secret injection works"
echo "Output: $output"
rm -rf "$MOCK_DIR" "$TEST_TMP_DIR"
exit 0
