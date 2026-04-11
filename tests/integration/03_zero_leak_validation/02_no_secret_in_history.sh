#!/bin/bash

# Integration Test: Zero-Leak - No Secrets in Shell History
# Verifies shell history doesn't contain secrets

set -euo pipefail

# Project root is three levels up from test script
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/secret-mgmt-integration-test}"
mkdir -p "$TEST_TMP_DIR"

echo "Testing zero-leak: secrets not in shell history..."

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

# Run a doppler command
doppler run -- echo "test" > /dev/null 2>&1 || true

# Check shell history
HISTORY_FILES=("$HOME/.bash_history" "$HOME/.zsh_history")
leaked=false

for hist_file in "${HISTORY_FILES[@]}"; do
    if [[ -f "$hist_file" ]] && [[ -s "$hist_file" ]]; then
        if grep -lE "(API_KEY|SECRET|PASSWORD|TOKEN).*=" "$hist_file" 2>/dev/null; then
            leaked=true
            echo "FAIL: Potential secrets found in $hist_file"
        fi
    fi
done

if [[ "$leaked" == "true" ]]; then
    rm -rf "$MOCK_DIR"
    exit 1
fi

echo "PASS: No secrets in shell history"
rm -rf "$MOCK_DIR"
exit 0
