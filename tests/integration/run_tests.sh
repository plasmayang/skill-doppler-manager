#!/bin/bash

# Doppler Manager - Integration Test Runner
# End-to-end integration tests for secret management workflows

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_DIR="$SCRIPT_DIR"
TEST_TMP_DIR="$TEST_DIR/tmp"
COVERAGE_DIR="$TEST_DIR/coverage"
PARALLEL_JOBS="${PARALLEL_JOBS:-4}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test state
FAILED_TESTS=()

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Cleanup on exit
cleanup() {
    if [[ -d "$TEST_TMP_DIR" ]]; then
        rm -rf "$TEST_TMP_DIR"
    fi
}
trap cleanup EXIT

# Setup test environment
setup() {
    info "Setting up integration test environment..."
    mkdir -p "$TEST_TMP_DIR"
    mkdir -p "$COVERAGE_DIR"

    # Initialize audit directory
    export DOPPLER_AUDIT_DIR="$TEST_TMP_DIR/audit"
    mkdir -p "$DOPPLER_AUDIT_DIR"

    # Initialize incident directory
    export DOPPLER_INCIDENT_DIR="$TEST_TMP_DIR/incidents"
    mkdir -p "$DOPPLER_INCIDENT_DIR"
}

# Mock doppler for testing
create_mock_doppler() {
    local mock_dir="$TEST_TMP_DIR/mock_bin"
    mkdir -p "$mock_dir"

    cat << 'EOF' > "$mock_dir/doppler"
#!/bin/bash
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
        if [[ "$2" == "get" ]]; then
            echo "mock_secret_value"
        fi
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
EOF
    chmod +x "$mock_dir/doppler"

    export PATH="$mock_dir:$PATH"
}

# Run a single test
run_test() {
    local test_name="$1"
    local test_script="$2"

    TESTS_RUN=$((TESTS_RUN + 1))

    echo ""
    echo "=============================================="
    echo "  Running: $test_name"
    echo "=============================================="

    local output
    local exit_code=0

    output=$(bash "$test_script" 2>&1) || exit_code=$?

    if [[ "$exit_code" -eq 0 ]]; then
        pass "$test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        fail "$test_name (exit code: $exit_code)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$test_name")
        echo "$output" | head -20
        return 1
    fi
}

# Run tests in a category
run_category() {
    local category="$1"
    local category_dir="$TEST_DIR/$category"

    if [[ ! -d "$category_dir" ]]; then
        warn "Category directory not found: $category"
        return 0
    fi

    echo ""
    echo "=============================================="
    echo "  Category: $category"
    echo "=============================================="

    local category_passed=0
    local category_failed=0

    for test_script in "$category_dir"/*.sh; do
        if [[ -f "$test_script" ]]; then
            local test_name
            test_name=$(basename "$test_script" .sh)

            if run_test "$category/$test_name" "$test_script"; then
                category_passed=$((category_passed + 1))
            else
                category_failed=$((category_failed + 1))
            fi
        fi
    done

    echo ""
    echo "Category summary: $category_passed passed, $category_failed failed"

    return $category_failed
}

# Print summary
print_summary() {
    echo ""
    echo "=============================================="
    echo "  Integration Test Summary"
    echo "=============================================="
    echo ""
    echo "Total tests run: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo ""

    if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
        echo -e "${RED}Failed tests:${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
        echo ""
    fi

    if [[ "$TESTS_FAILED" -eq 0 ]]; then
        pass "All integration tests passed!"
        return 0
    else
        fail "Some integration tests failed"
        return 1
    fi
}

# Usage
usage() {
    cat <<EOF
Doppler Manager - Integration Test Runner

Usage: $(basename "$0") [options] [categories...]

Options:
  -h, --help              Show this help message
  -v, --verbose           Verbose output
  -j, --jobs N            Number of parallel jobs (default: $PARALLEL_JOBS)
  -l, --list              List all available tests
  --no-cleanup            Don't cleanup temp files after test

Categories:
  01_install_auth         Installation and authentication tests
  02_secret_injection     Secret injection workflow tests
  03_zero_leak_validation Zero-Leak verification tests
  04_hitl_workflow       Human-in-the-loop workflow tests
  05_incident_response    Incident response tests

Examples:
  $(basename "$0")                    # Run all tests
  $(basename "$0") 01_install_auth   # Run only install/auth tests
  $(basename "$0") -l                # List all available tests
  $(basename "$0") -j 8 03_zero_leak_validation  # Run with 8 parallel jobs

EOF
}

# List available tests
list_tests() {
    echo "Available integration tests:"
    echo ""

    for category_dir in "$TEST_DIR"/[0-9]*; do
        if [[ -d "$category_dir" ]]; then
            local category
            category=$(basename "$category_dir")
            echo "$category:"

            for test_script in "$category_dir"/*.sh; do
                if [[ -f "$test_script" ]]; then
                    local test_name
                    test_name=$(basename "$test_script" .sh)
                    echo "  - $test_name"
                fi
            done
            echo ""
        fi
    done
}

# Main
main() {
    local verbose=false
    local no_cleanup=false
    local categories=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -j|--jobs)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            -l|--list)
                list_tests
                exit 0
                ;;
            --no-cleanup)
                no_cleanup=true
                trap - EXIT
                shift
                ;;
            *)
                categories+=("$1")
                shift
                ;;
        esac
    done

    # Setup
    setup

    # Default to all categories if none specified
    if [[ ${#categories[@]} -eq 0 ]]; then
        categories=(01_install_auth 02_secret_injection 03_zero_leak_validation 04_hitl_workflow 05_incident_response)
    fi

    # Run categories
    local total_failed=0

    for category in "${categories[@]}"; do
        if ! run_category "$category"; then
            total_failed=$((total_failed + 1))
        fi
    done

    # Print summary
    print_summary

    # Exit with appropriate code
    if [[ "$TESTS_FAILED" -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
