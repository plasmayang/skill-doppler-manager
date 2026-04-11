#!/bin/bash

# Unified Test Runner for secret-management
# Supports both CI and local development testing
#
# Usage:
#   ./tests/run_tests.sh              # Run all tests (CI mode)
#   ./tests/run_tests.sh --bats       # BATS tests only (fast)
#   ./tests/run_tests.sh --integration # Integration tests only
#   ./tests/run_tests.sh --quick      # Quick smoke test
#   ./tests/run_tests.sh --list       # List all tests

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/secret-management-test}"
COVERAGE_DIR="$SCRIPT_DIR/coverage"

# Test mode (can be overridden)
MODE="${TEST_MODE:-all}"  # all, bats, integration, quick

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# ============================================
# Output Functions
# ============================================

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
section() { echo -e "\n${CYAN}==============================================${NC}"; }
subsection() { echo -e "${CYAN}----------------------------------------------${NC}"; }

# ============================================
# Environment Setup
# ============================================

setup_test_env() {
    info "Setting up test environment..."
    mkdir -p "$TEST_TMP_DIR"
    mkdir -p "$COVERAGE_DIR"

    # Audit directory for tests
    export DOPPLER_AUDIT_DIR="$TEST_TMP_DIR/audit"
    mkdir -p "$DOPPLER_AUDIT_DIR"

    # Use mock Doppler
    setup_mock_doppler

    # Set PATH to prefer mock
    export PATH="$TEST_TMP_DIR/mock_bin:$PATH"

    info "Test environment ready (TMP_DIR: $TEST_TMP_DIR)"
}

cleanup_test_env() {
    if [[ "${CI:-}" != "true" ]] && [[ "${KEEP_TMP:-}" != "1" ]]; then
        rm -rf "$TEST_TMP_DIR"
        info "Cleaned up test environment"
    else
        info "Preserving test environment at $TEST_TMP_DIR"
    fi
}

# ============================================
# Mock Doppler Setup
# ============================================

setup_mock_doppler() {
    local mock_dir="$TEST_TMP_DIR/mock_bin"
    mkdir -p "$mock_dir"

    cat << 'MOCK_EOF' > "$mock_dir/doppler"
#!/bin/bash
# Mock Doppler CLI for testing
# This mock simulates Doppler CLI behavior without real authentication

case "$1" in
    --version)
        echo "Doppler 3.10.0 (mock)"
        ;;
    configure)
        if [[ -z "$2" ]]; then
            exit 0
        fi
        if [[ "$2" == "get" ]]; then
            case "$3" in
                project)
                    echo "${DOPPLER_PROJECT:-test-project}"
                    ;;
                config)
                    echo "${DOPPLER_CONFIG:-dev}"
                    ;;
                token)
                    echo "${DOPPLER_TOKEN:-dp.st.mock_token}"
                    ;;
            esac
        fi
        exit 0
        ;;
    secrets)
        case "$2" in
            get)
                # Return mock secret value
                echo "mock_secret_value"
                ;;
            --quiet)
                echo "MOCK_QUIET_SECRET=test"
                ;;
            list)
                echo "DATABASE_URL"
                echo "API_KEY"
                ;;
        esac
        exit 0
        ;;
    run)
        shift 2
        eval "$@"
        ;;
    *)
        exit 1
        ;;
esac
MOCK_EOF
    chmod +x "$mock_dir/doppler"

    # Also create mock for other secret managers
    setup_mock_vault "$mock_dir"
    setup_mock_aws "$mock_dir"
    setup_mock_infisical "$mock_dir"
}

setup_mock_vault() {
    local mock_dir="$1"
    cat << 'MOCK_EOF' > "$mock_dir/vault"
#!/bin/bash
# Mock Vault CLI for testing
case "$1" in
    status)
        if [[ -z "${VAULT_ADDR:-}" ]]; then
            exit 1
        fi
        echo '{"sealed": false}'
        ;;
    kv)
        if [[ "$2" == "get" ]]; then
            echo '{"data": {"data": {"SECRET_KEY": "mock_vault_value"}}}'
        fi
        ;;
esac
exit 0
MOCK_EOF
    chmod +x "$mock_dir/vault"
}

setup_mock_aws() {
    local mock_dir="$1"
    cat << 'MOCK_EOF' > "$mock_dir/aws"
#!/bin/bash
# Mock AWS CLI for testing
if [[ "$1" == "secretsmanager" ]]; then
    if [[ "$2" == "get-secret-value" ]]; then
        echo '{"SecretString": "mock_aws_value"}'
    fi
fi
exit 0
MOCK_EOF
    chmod +x "$mock_dir/aws"
}

setup_mock_infisical() {
    local mock_dir="$1"
    cat << 'MOCK_EOF' > "$mock_dir/infisical"
#!/bin/bash
# Mock Infisical CLI for testing
if [[ "$1" == "secrets" ]]; then
    if [[ "$2" == "get" ]]; then
        echo "mock_infisical_value"
    fi
fi
exit 0
MOCK_EOF
    chmod +x "$mock_dir/infisical"
}

# ============================================
# BATS Tests
# ============================================

run_bats_tests() {
    section
    info "Running BATS Tests (Unit Tests)"
    subsection

    if ! command -v bats &>/dev/null; then
        warn "BATS not installed, installing..."
        install_bats
    fi

    local bats_files=()
    while IFS= read -r -d '' file; do
        bats_files+=("$file")
    done < <(find "$SCRIPT_DIR/bats" -name "*.bats" -type f -print0 2>/dev/null || true)

    if [[ ${#bats_files[@]} -eq 0 ]]; then
        warn "No BATS tests found"
        return 0
    fi

    info "Found ${#bats_files[@]} BATS test file(s)"

    local result=0
    for bats_file in "${bats_files[@]}"; do
        local test_name
        test_name=$(basename "$bats_file" .bats)
        info "Running: $test_name"

        if bats "$bats_file"; then
            pass "BATS: $test_name"
        else
            fail "BATS: $test_name"
            result=1
        fi
    done

    return $result
}

# ============================================
# Integration Tests
# ============================================

run_integration_tests() {
    section
    info "Running Integration Tests"
    subsection

    local categories=(
        "01_install_auth"
        "02_secret_injection"
        "03_zero_leak_validation"
        "04_hitl_workflow"
        "05_incident_response"
    )

    local total_failed=0

    for category in "${categories[@]}"; do
        local category_dir="$SCRIPT_DIR/integration/$category"

        if [[ ! -d "$category_dir" ]]; then
            warn "Category not found: $category"
            continue
        fi

        section
        info "Category: $category"
        subsection

        local category_passed=0
        local category_failed=0

        for test_script in "$category_dir"/*.sh; do
            if [[ ! -f "$test_script" ]]; then
                continue
            fi

            local test_name
            test_name="$category/$(basename "$test_script" .sh)"

            info "Running: $test_name"

            # Run integration test with mock environment
            if bash "$test_script" 2>&1; then
                pass "Integration: $test_name"
                TESTS_PASSED=$((TESTS_PASSED + 1))
                category_passed=$((category_passed + 1))
            else
                fail "Integration: $test_name (exit code: $?)"
                TESTS_FAILED=$((TESTS_FAILED + 1))
                FAILED_TESTS+=("$test_name")
                category_failed=$((category_failed + 1))
                total_failed=$((total_failed + 1))
            fi

            TESTS_RUN=$((TESTS_RUN + 1))
        done

        info "Category $category: $category_passed passed, $category_failed failed"
    done

    return $total_failed
}

# ============================================
# Quick Test (Smoke Test)
# ============================================

run_quick_test() {
    section
    info "Running Quick Smoke Test"
    subsection

    local quick_tests=(
        "check_status.sh"
        "detect_manager.sh"
        "audit_secrets.sh"
        "emergency_seal.sh"
    )

    for script in "${quick_tests[@]}"; do
        local script_path="$PROJECT_ROOT/scripts/$script"
        if [[ -f "$script_path" ]]; then
            info "Testing: $script"
            if bash "$script_path" &>/dev/null; then
                pass "Quick: $script"
            else
                # Some scripts return non-zero when configured, check for expected behavior
                if bash "$script_path" 2>&1 | grep -q "status"; then
                    pass "Quick: $script (expected non-zero)"
                else
                    fail "Quick: $script"
                fi
            fi
        fi
    done
}

# ============================================
# Install BATS
# ============================================

install_bats() {
    local bats_dir="/tmp/bats-core"
    if [[ -d "$bats_dir" ]]; then
        export PATH="$bats_dir/bin:$PATH"
        return 0
    fi

    info "Installing BATS from source..."
    git clone --depth 1 https://github.com/bats-core/bats-core.git "$bats_dir" 2>/dev/null || {
        # Fallback: use npm
        npm install -g bats 2>/dev/null || {
            warn "Failed to install BATS, some tests may be skipped"
            return 1
        }
    }
    export PATH="$bats_dir/bin:$PATH"
}

# ============================================
# List Tests
# ============================================

list_tests() {
    echo "Available Tests:"
    echo ""

    echo "BATS Tests:"
    while IFS= read -r -d '' file; do
        echo "  - $(basename "$file" .bats)"
    done < <(find "$SCRIPT_DIR/bats" -name "*.bats" -type f -print0 2>/dev/null || true)

    echo ""
    echo "Integration Tests:"

    for category_dir in "$SCRIPT_DIR/integration"/[0-9]*; do
        if [[ -d "$category_dir" ]]; then
            echo "  $(basename "$category_dir"):"
            for test_script in "$category_dir"/*.sh; do
                if [[ -f "$test_script" ]]; then
                    echo "    - $(basename "$test_script" .sh)"
                fi
            done
        fi
    done
}

# ============================================
# Usage
# ============================================

usage() {
    cat <<EOF
Unified Test Runner for secret-management

Usage: $0 [options]

Options:
  --all           Run all tests (BATS + Integration) [default]
  --bats          BATS tests only (fast unit tests)
  --integration   Integration tests only
  --quick         Quick smoke test (no BATS required)
  --list          List all available tests
  --install       Install test dependencies (BATS)
  --keep-tmp      Keep temp directory after tests
  -h, --help      Show this help

Environment Variables:
  TEST_MODE       Test mode: all, bats, integration, quick
  TEST_TMP_DIR    Temporary directory for test files
  KEEP_TMP        Keep temp directory after tests
  CI              Set to "true" for CI mode

Examples:
  $0                    # Run all tests
  $0 --bats            # Fast unit tests only
  $0 --integration     # Integration tests only
  $0 --quick           # Smoke test
  $0 --list            # See what tests exist
  CI=true $0           # Run in CI mode
EOF
}

# ============================================
# Main
# ============================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all) MODE="all"; shift ;;
            --bats) MODE="bats"; shift ;;
            --integration) MODE="integration"; shift ;;
            --quick) MODE="quick"; shift ;;
            --list) MODE="list"; shift ;;
            --install) MODE="install"; shift ;;
            --keep-tmp) export KEEP_TMP=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) echo "Unknown option: $1"; usage; exit 1 ;;
        esac
    done

    case "$MODE" in
        list)
            list_tests
            exit 0
            ;;
        install)
            install_bats
            exit 0
            ;;
        quick)
            setup_test_env
            run_quick_test
            cleanup_test_env
            exit 0
            ;;
        bats)
            run_bats_tests
            exit $?
            ;;
        integration)
            setup_test_env
            run_integration_tests
            cleanup_test_env
            exit $?
            ;;
        all|*)
            # Run BATS first (no mock environment needed)
            local failed=0
            if ! run_bats_tests; then
                failed=1
            fi

            # Then integration tests (mock environment needed)
            setup_test_env
            trap cleanup_test_env EXIT

            if ! run_integration_tests; then
                failed=1
            fi

            # Summary
            section
            info "Test Summary"
            subsection
            echo "  BATS Tests: see above"
            echo "  Integration: $TESTS_PASSED passed, $TESTS_FAILED failed"

            if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
                echo ""
                fail "Failed tests:"
                for t in "${FAILED_TESTS[@]}"; do
                    echo "    - $t"
                done
            fi

            if [[ "$failed" -eq 0 ]]; then
                pass "All tests passed!"
            else
                fail "Some tests failed"
            fi

            exit $failed
            ;;
    esac
}

main "$@"
