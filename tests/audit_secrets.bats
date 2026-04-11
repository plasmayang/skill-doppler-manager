#!/usr/bin/env bats

# BATS test suite for scripts/audit_secrets.sh
# Tests secret access audit logging functionality

setup() {
    # Create temporary audit directory for testing
    export TEST_AUDIT_DIR="$(mktemp -d)"
    export DOPPLER_AUDIT_DIR="$TEST_AUDIT_DIR"
    # Ensure subdirectories exist
    mkdir -p "$TEST_AUDIT_DIR"
}

teardown() {
    rm -rf "$TEST_AUDIT_DIR"
}

# Load the script
SCRIPT="./scripts/audit_secrets.sh"

@test "audit_secrets: shows usage when no arguments provided" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"access"* ]]
    [[ "$output" == *"leak"* ]]
    [[ "$output" == *"auth"* ]]
}

@test "audit_secrets: access command logs secret access event" {
    run bash "$SCRIPT" access "DATABASE_URL" "doppler_run" "true"
    [ "$status" -eq 0 ]

    # Verify audit log file exists
    [ -f "$TEST_AUDIT_DIR/audit.log" ]

    # Verify the log entry contains expected fields
    local log_entry
    log_entry=$(tail -n 1 "$TEST_AUDIT_DIR/audit.log")
    [[ "$log_entry" == *"SECRET_ACCESS"* ]]
    [[ "$log_entry" == *"DATABASE_URL"* ]]
    [[ "$log_entry" == *"doppler_run"* ]]
    [[ "$log_entry" == *'"success": true'* ]]
}

@test "audit_secrets: access command with error logs failure" {
    run bash "$SCRIPT" access "API_KEY" "doppler_run" "false" "Permission denied"
    [ "$status" -eq 0 ]

    local log_entry
    log_entry=$(tail -n 1 "$TEST_AUDIT_DIR/audit.log")
    [[ "$log_entry" == *'"success": false'* ]]
    [[ "$log_entry" == *"Permission denied"* ]]
}

@test "audit_secrets: leak command logs to alert log" {
    run bash "$SCRIPT" leak "PASTED_SECRET" "User pasted secret in chat" "HIGH"
    [ "$status" -eq 0 ]

    # Verify alert log file exists
    [ -f "$TEST_AUDIT_DIR/alerts.log" ]

    local alert_entry
    alert_entry=$(tail -n 1 "$TEST_AUDIT_DIR/alerts.log")
    [[ "$alert_entry" == *"LEAK_DETECTED"* ]]
    [[ "$alert_entry" == *"PASTED_SECRET"* ]]
    [[ "$alert_entry" == *"HIGH"* ]]
}

@test "audit_secrets: leak command defaults severity to MEDIUM" {
    run bash "$SCRIPT" leak "ACCIDENTAL_ECHO"
    [ "$status" -eq 0 ]

    local alert_entry
    alert_entry=$(tail -n 1 "$TEST_AUDIT_DIR/alerts.log")
    [[ "$alert_entry" == *'"severity": "MEDIUM"'* ]]
}

@test "audit_secrets: auth command logs authentication event" {
    run bash "$SCRIPT" auth "service_token" "true" "service-account" "prod-project"
    [ "$status" -eq 0 ]

    [ -f "$TEST_AUDIT_DIR/audit.log" ]

    local auth_entry
    auth_entry=$(tail -n 1 "$TEST_AUDIT_DIR/audit.log")
    [[ "$auth_entry" == *"AUTH_EVENT"* ]]
    [[ "$auth_entry" == *"service_token"* ]]
    [[ "$auth_entry" == *'"success": true'* ]]
}

@test "audit_secrets: auth command without user/project logs minimal entry" {
    run bash "$SCRIPT" auth "interactive_login" "false"
    [ "$status" -eq 0 ]

    local auth_entry
    auth_entry=$(tail -n 1 "$TEST_AUDIT_DIR/audit.log")
    [[ "$auth_entry" == *"AUTH_EVENT"* ]]
    [[ "$auth_entry" == *"interactive_login"* ]]
    [[ "$auth_entry" == *'"success": false'* ]]
}

@test "audit_secrets: exec command logs command execution" {
    run bash "$SCRIPT" exec "doppler run -- python deploy.py" "/home/user/project" "true" "0"
    [ "$status" -eq 0 ]

    [ -f "$TEST_AUDIT_DIR/audit.log" ]

    local exec_entry
    exec_entry=$(tail -n 1 "$TEST_AUDIT_DIR/audit.log")
    [[ "$exec_entry" == *"COMMAND_EXEC"* ]]
    [[ "$exec_entry" == *"doppler run -- python deploy.py"* ]]
    [[ "$exec_entry" == *'/home/user/project'* ]]
    [[ "$exec_entry" == *'"exit_code": 0'* ]]
}

@test "audit_secrets: exec command logs failed execution" {
    run bash "$SCRIPT" exec "doppler run -- npm test" "/home/user/project" "false" "1"
    [ "$status" -eq 0 ]

    local exec_entry
    exec_entry=$(tail -n 1 "$TEST_AUDIT_DIR/audit.log")
    [[ "$exec_entry" == *'"success": false'* ]]
    [[ "$exec_entry" == *'"exit_code": 1'* ]]
}

@test "audit_secrets: view command shows recent logs" {
    # First create some log entries
    bash "$SCRIPT" access "SECRET1" "test" "true"
    bash "$SCRIPT" access "SECRET2" "test" "true"
    bash "$SCRIPT" auth "token" "true"

    run bash "$SCRIPT" view 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"Recent Audit Logs"* ]]
}

@test "audit_secrets: alerts command shows security alerts" {
    # Create an alert
    bash "$SCRIPT" leak "TEST_LEAK" "Test context"

    run bash "$SCRIPT" alerts
    [ "$status" -eq 0 ]
    [[ "$output" == *"Security Alerts"* ]]
    [[ "$output" == *"TEST_LEAK"* ]]
}

@test "audit_secrets: export command copies logs to file" {
    # Create some log entries
    bash "$SCRIPT" access "SECRET1" "test" "true"

    local export_file="$TEST_AUDIT_DIR/exported.jsonl"
    run bash "$SCRIPT" export "$export_file"
    [ "$status" -eq 0 ]
    [ -f "$export_file" ]

    # Verify content was copied
    local exported_content
    exported_content=$(cat "$export_file")
    [[ "$exported_content" == *"SECRET1"* ]]
}

@test "audit_secrets: export without argument uses default filename" {
    bash "$SCRIPT" access "SECRET1" "test" "true"

    run bash "$SCRIPT" export
    [ "$status" -eq 0 ]
    [ -f "$TEST_AUDIT_DIR/doppler-audit-export.jsonl" ]
}

@test "audit_secrets: clean command removes old entries" {
    # Create entries - we need to manually add old entries for testing
    # Since clean_logs filters by timestamp, we test the function exists and runs

    run bash "$SCRIPT" clean 30
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cleaned logs older than"* ]]
}

@test "audit_secrets: log entries are valid JSONL" {
    bash "$SCRIPT" access "DATABASE_URL" "doppler_run" "true"
    bash "$SCRIPT" auth "service_token" "true"
    bash "$SCRIPT" exec "ls" "/tmp" "true" "0"

    # Verify each line is valid JSON
    while IFS= read -r line; do
        echo "$line" | python3 -c "import json,sys; json.load(sys.stdin)"
    done < "$TEST_AUDIT_DIR/audit.log"
    [ "$status" -eq 0 ]
}

@test "audit_secrets: log entries contain required fields" {
    bash "$SCRIPT" access "API_KEY" "doppler_run" "true"

    local log_entry
    log_entry=$(tail -n 1 "$TEST_AUDIT_DIR/audit.log")

    # Check for required fields
    [[ "$log_entry" == *'"id":'* ]]
    [[ "$log_entry" == *'"timestamp":'* ]]
    [[ "$log_entry" == *'"type":'* ]]
    [[ "$log_entry" == *'"data":'* ]]
    [[ "$log_entry" == *'"agent": "doppler-manager-skill"'* ]]
    [[ "$log_entry" == *'"version": "1.0.0"'* ]]
}

@test "audit_secrets: multiple sequential entries are appended" {
    bash "$SCRIPT" access "SECRET_A" "test" "true"
    bash "$SCRIPT" access "SECRET_B" "test" "true"
    bash "$SCRIPT" access "SECRET_C" "test" "true"

    local line_count
    line_count=$(wc -l < "$TEST_AUDIT_DIR/audit.log")
    [ "$line_count" -eq 3 ]
}

@test "audit_secrets: UNKNOWN is used as default secret name" {
    run bash "$SCRIPT" access
    [ "$status" -eq 0 ]

    local log_entry
    log_entry=$(tail -n 1 "$TEST_AUDIT_DIR/audit.log")
    [[ "$log_entry" == *'"secret_name": "UNKNOWN"'* ]]
}

@test "audit_secrets: handles special characters in secret names" {
    run bash "$SCRIPT" access "MY-SECRET_123" "doppler_run" "true"
    [ "$status" -eq 0 ]

    local log_entry
    log_entry=$(tail -n 1 "$TEST_AUDIT_DIR/audit.log")
    [[ "$log_entry" == *"MY-SECRET_123"* ]]
}

@test "audit_secrets: timestamp is in ISO 8601 format" {
    bash "$SCRIPT" access "SECRET" "test" "true"

    local log_entry
    log_entry=$(tail -n 1 "$TEST_AUDIT_DIR/audit.log")

    # Extract timestamp field and validate format
    local timestamp
    timestamp=$(echo "$log_entry" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('timestamp',''))")
    [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}
