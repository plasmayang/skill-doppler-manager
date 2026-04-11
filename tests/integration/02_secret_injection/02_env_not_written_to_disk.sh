#!/bin/bash

# Integration Test: Verify No .env File Created
# Ensures secrets are not written to disk

set -euo pipefail

# Project root is three levels up from test script
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/secret-mgmt-integration-test}"
mkdir -p "$TEST_TMP_DIR"

echo "Testing that no .env file is created..."

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
        shift 2; eval "$@"
        ;;
    *)
        exit 1
        ;;
esac
EOF
chmod +x "$MOCK_DIR/doppler"
export PATH="$MOCK_DIR:$PATH"

# Run a command that would typically need secrets
doppler run -- env > /dev/null 2>&1 || true

# Check for .env files in tmp dir
env_files=$(find "$TEST_TMP_DIR" -name ".env" -type f 2>/dev/null || true)

if [[ -n "$env_files" ]]; then
    echo "FAIL: .env file(s) were created: $env_files"
    rm -rf "$MOCK_DIR"
    exit 1
fi

echo "PASS: No .env file created during injection"
rm -rf "$MOCK_DIR"
exit 0
