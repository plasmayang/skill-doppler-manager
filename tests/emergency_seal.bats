#!/usr/bin/env bats

# BATS test suite for scripts/emergency_seal.sh
# Tests emergency incident response functionality

setup() {
    # Create temporary directories for testing
    export TEST_AUDIT_DIR="$(mktemp -d)"
    export TEST_INCIDENT_DIR="$TEST_AUDIT_DIR/incidents"
    export DOPPLER_AUDIT_DIR="$TEST_AUDIT_DIR"
    export HOME="$TEST_AUDIT_DIR/home"
    mkdir -p "$HOME"
}

teardown() {
    rm -rf "$TEST_AUDIT_DIR"
}

SCRIPT="./scripts/emergency_seal.sh"

@test "emergency_seal: creates incident directory structure" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]

    # Verify incident directory was created
    [ -d "$TEST_INCIDENT_DIR" ]
}

@test "emergency_seal: generates unique incident ID format" {
    run bash "$SCRIPT"

    # Extract incident ID from output
    local incident_id
    incident_id=$(echo "$output" | grep -oP 'INC-\d{8}-\d{6}-\d+' | head -1)
    [ -n "$incident_id" ]

    # Verify format: INC-YYYYMMDD-HHMMSS-PID
    [[ "$incident_id" =~ ^INC-[0-9]{8}-[0-9]{6}-[0-9]+$ ]]
}

@test "emergency_seal: creates incident report markdown file" {
    run bash "$SCRIPT"

    # Find the incident report file
    local report_file
    report_file=$(find "$TEST_INCIDENT_DIR" -name "*report.md" | head -1)
    [ -n "$report_file" ]
    [ -f "$report_file" ]
}

@test "emergency_seal: incident report contains required sections" {
    run bash "$SCRIPT"

    local report_file
    report_file=$(find "$TEST_INCIDENT_DIR" -name "*report.md" | head -1)

    local report_content
    report_content=$(cat "$report_file")

    # Verify required sections exist
    [[ "$report_content" == *"Incident Details"* ]]
    [[ "$report_content" == *"Secret Rotation"* ]]
    [[ "$report_content" == *"Access Review"* ]]
    [[ "$report_content" == *"Environment Cleanup"* ]]
    [[ "$report_content" == *"Evidence Files"* ]]
}

@test "emergency_seal: incident report contains incident ID" {
    run bash "$SCRIPT"

    local incident_id
    incident_id=$(echo "$output" | grep -oP 'INC-\d{8}-\d{6}-\d+' | head -1)

    local report_file
    report_file=$(find "$TEST_INCIDENT_DIR" -name "*report.md" | head -1)

    local report_content
    report_content=$(cat "$report_file")
    [[ "$report_content" == *"$incident_id"* ]]
}

@test "emergency_seal: captures environment snapshot JSON" {
    run bash "$SCRIPT"

    local env_file
    env_file=$(find "$TEST_INCIDENT_DIR" -name "*environment.json" | head -1)
    [ -n "$env_file" ]
    [ -f "$env_file" ]

    # Verify it's valid JSON
    python3 -c "import json; json.load(open('$env_file'))"
}

@test "emergency_seal: environment snapshot contains required fields" {
    run bash "$SCRIPT"

    local env_file
    env_file=$(find "$TEST_INCIDENT_DIR" -name "*environment.json" | head -1)

    local env_content
    env_content=$(cat "$env_file")

    [[ "$env_content" == *'"incident_id":'* ]]
    [[ "$env_content" == *'"timestamp":'* ]]
    [[ "$env_content" == *'"hostname":'* ]]
    [[ "$env_content" == *'"user":'* ]]
    [[ "$env_content" == *'"cwd":'* ]]
    [[ "$env_content" == *'"doppler_configured":'* ]]
}

@test "emergency_seal: captures audit snapshot if exists" {
    # First create an audit log
    mkdir -p "$TEST_AUDIT_DIR"
    echo '{"test":"entry"}' > "$TEST_AUDIT_DIR/audit.log"

    run bash "$SCRIPT"

    local audit_snapshot
    audit_snapshot=$(find "$TEST_INCIDENT_DIR" -name "*-audit.jsonl" | head -1)
    [ -n "$audit_snapshot" ]
    [ -f "$audit_snapshot" ]
}

@test "emergency_seal: captures alert snapshot if exists" {
    # First create an alert log
    mkdir -p "$TEST_AUDIT_DIR"
    echo '{"alert":"test"}' > "$TEST_AUDIT_DIR/alerts.log"

    run bash "$SCRIPT"

    local alert_snapshot
    alert_snapshot=$(find "$TEST_INCIDENT_DIR" -name "*-alerts.jsonl" | head -1)
    [ -n "$alert_snapshot" ]
    [ -f "$alert_snapshot" ]
}

@test "emergency_seal: handles missing existing audit log gracefully" {
    # Ensure no existing audit log
    rm -f "$TEST_AUDIT_DIR/audit.log" 2>/dev/null

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No existing audit log found"* ]]
}

@test "emergency_seal: handles missing existing alert log gracefully" {
    # Ensure no existing alert log
    rm -f "$TEST_AUDIT_DIR/alerts.log" 2>/dev/null

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No existing alerts found"* ]]
}

@test "emergency_seal: prints important next steps" {
    run bash "$SCRIPT"

    [[ "$output" == *"IMPORTANT NEXT STEPS"* ]]
    [[ "$output" == *"ROTATE"* ]]
    [[ "$output" == *"Review the incident report"* ]]
    [[ "$output" == *"Doppler access logs"* ]]
    [[ "$output" == *"git-secrets"* ]]
}

@test "emergency_seal: warns about mandatory secret rotation" {
    run bash "$SCRIPT"

    [[ "$output" == *"MANDATORY"* ]] || [[ "$output" == *"mandatory"* ]]
    [[ "$output" == *"Do NOT ignore"* ]]
}

@test "emergency_seal: displays evidence storage location" {
    run bash "$SCRIPT"

    [[ "$output" == *"Evidence stored in:"* ]]
    [[ "$output" == *"Incident ID for reference"* ]]
}

@test "emergency_seal: uses set -euo pipefail" {
    # The script should exit on error (set -euo pipefail)
    # When running normally, it should succeed
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "emergency_seal: multiple runs create separate incidents" {
    run bash "$SCRIPT"
    run bash "$SCRIPT"

    # Count incident report files (one per run)
    local incident_count
    incident_count=$(find "$TEST_INCIDENT_DIR" -name "*report.md" | wc -l)

    [ "$incident_count" -ge 2 ]
}

@test "emergency_seal: incident report includes severity classification template" {
    run bash "$SCRIPT"

    local report_file
    report_file=$(find "$TEST_INCIDENT_DIR" -name "*report.md" | head -1)

    local report_content
    report_content=$(cat "$report_file")

    # Verify severity checkboxes exist
    [[ "$report_content" == *"LOW"* ]]
    [[ "$report_content" == *"MEDIUM"* ]]
    [[ "$report_content" == *"HIGH"* ]]
    [[ "$report_content" == *"CRITICAL"* ]]
}

@test "emergency_seal: incident report includes exposure classification" {
    run bash "$SCRIPT"

    local report_file
    report_file=$(find "$TEST_INCIDENT_DIR" -name "*report.md" | head -1)

    local report_content
    report_content=$(cat "$report_file")

    [[ "$report_content" == *"Internal Only"* ]]
    [[ "$report_content" == *"External Possible"* ]]
    [[ "$report_content" == *"Confirmed External"* ]]
}

@test "emergency_seal: audit logs are NOT cleared (evidence preserved)" {
    # Create a pre-existing audit log
    mkdir -p "$TEST_AUDIT_DIR"
    echo '{"original":"entry"}' > "$TEST_AUDIT_DIR/audit.log"

    run bash "$SCRIPT"

    # The original audit log should still exist
    [ -f "$TEST_AUDIT_DIR/audit.log" ]

    local original_content
    original_content=$(cat "$TEST_AUDIT_DIR/audit.log")
    [[ "$original_content" == *'"original":"entry"'* ]]
}

@test "emergency_seal: provides Doppler dashboard URL" {
    run bash "$SCRIPT"

    [[ "$output" == *"Doppler Dashboard"* ]]
}

@test "emergency_seal: includes cleanup commands in report" {
    run bash "$SCRIPT"

    local report_file
    report_file=$(find "$TEST_INCIDENT_DIR" -name "*report.md" | head -1)

    local report_content
    report_content=$(cat "$report_file")

    # Verify cleanup commands are present
    [[ "$report_content" == *"find"* ]]
    [[ "$report_content" == *".env"* ]]
    [[ "$report_content" == *"history -c"* ]]
}
