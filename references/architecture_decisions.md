# Doppler Manager Architecture & Design Decisions

## Core Intent

This skill acts as the "hand" for an LLM to manage secrets using Doppler. It is intentionally designed to be an orchestrator, not a policy engine.

## The Scope Boundary (Why we removed the 9-Grid)

Earlier iterations of this skill included a "9-Grid Architecture" for secret classification. We have explicitly removed this because:

1. **Separation of Concerns:** How a user classifies and organizes their secrets (e.g., 9-Grid, by-service, by-environment) is a *human policy* decision. This skill's responsibility is purely operational—how to securely fetch and inject those secrets, regardless of the underlying organizational schema.
2. **Context Economy:** Hardcoding specific architectures into the AI's prompt wastes valuable token context on rules that may not apply to every user's workspace.

## Prompt vs. Code: What goes where?

To ensure this skill remains performant, secure, and maintainable, we strictly divide responsibilities between the AI Prompt (`SKILL.md`) and executable scripts (`scripts/`).

### 1. Solidified into Prompt (`SKILL.md`)

The prompt is reserved for behavioral guardrails, cognitive workflows, and interaction protocols that require LLM reasoning.

- **The Prime Directive (Zero-Leak):** The absolute rule never to print, log, or write secrets to disk (e.g., `.env` files).
- **The Injection Workflow:** The mandate to use `doppler run -- <command>` for execution.
- **Human-in-the-Loop (HITL) Triggers:** When and how to use the `ask_user` tool (e.g., requesting authorization before injecting secrets into a new service, or asking the user to manually add a secret via the CLI).
- **Error Handling Strategy:** How the AI should react when a Doppler command fails (e.g., checking auth status).

### 2. Solidified into Code (`scripts/`)

Executable code handles deterministic state checks, formatting, and operations that do not require LLM reasoning.

- **Environment Verification (`check_status.sh`):** Determines if the CLI is installed and authenticated. By pushing this to a script, we guarantee a deterministic, LLM-friendly output (`STATUS: OK / ERROR`), preventing the LLM from hallucinating terminal output or wasting tokens parsing verbose help menus.
- **Future Automation:** Any complex multi-step CLI sequence that doesn't require dynamic LLM decision-making should be encapsulated in a bash or python script within this directory.

### 3. Solidified into Documentation (`references/SOP.md`)

Documentation is for human operators and for the LLM to read *only when explicitly needed* (e.g., during initial setup).

- **Installation Commands:** OS-specific curl/apt/brew commands for installing the Doppler CLI.
- **Authentication Guides:** How a human should generate a Service Token or use `doppler login`.
- *(Historical Note: We have scrubbed all historical project-specific baggage, such as "iron-web-core" or personal homelab setups, to ensure this skill is a generic, open-source primitive.)*

---

## ADR-010: OpenTelemetry Tracing Approach

**Date**: 2026-04-11
**Status**: Accepted

### Context

As the skill grows in complexity, debugging skill behavior becomes difficult. We need observability into:

- Which scripts are being called
- How secrets are accessed
- Where errors occur in the execution flow

### Decision

We implement a lightweight tracing wrapper (`scripts/tracing.sh`) with these properties:

1. **Opt-in tracing**: Tracing only activates when `OTEL_ENDPOINT` is set
2. **Graceful degradation**: When tracing is disabled, scripts work normally
3. **JSONL audit trail**: Spans are exportable in OpenTelemetry format
4. **Minimal overhead**: Uses only bash, no external dependencies

### Consequences

- **Positive**: Debugging becomes possible without modifying script logic
- **Positive**: Audit logs can be correlated with distributed traces
- **Negative**: Additional complexity in script sourcing
- **Negative**: Slight overhead when tracing is active

### Implementation

```bash
# Initialize tracing
source scripts/tracing.sh

# Wrap operations
trace_span "doppler.run"
doppler run -- "$@"
trace_end "$span_id" "OK"
```

---

## ADR-011: Multi-Secret-Manager Interface Design

**Date**: 2026-04-11
**Status**: Accepted

### Context

Users may want to use HashiCorp Vault, AWS Secrets Manager, or other secret managers alongside or instead of Doppler. The skill should support multiple managers without code duplication.

### Decision

We implement a **manager interface pattern**:

1. **Abstract interface** (`secret_manager_interface.sh`): Defines `sm_init`, `sm_status`, `sm_run`, `sm_get`, `sm_audit`, `sm_set`
2. **Manager implementations** (`managers/*.sh`): Each manager implements the interface
3. **Auto-detection** (`detect_manager.sh`): Discovers available managers and selects the best one

### Status JSON Contract

All managers MUST return status in this format:

```json
{
  "status": "OK|WARNING|ERROR",
  "code": "E000|E001|...",
  "message": "...",
  "hint": "...",
  "documentation": "...",
  "project": "...",
  "config": "...",
  "manager": "manager-name"
}
```

### Consequences

- **Positive**: Supports multiple secret managers seamlessly
- **Positive**: Easy to add new managers
- **Negative**: Interface adds abstraction overhead
- **Negative**: Requires careful adherence to contract

---

## ADR-012: Adversarial Testing Strategy

**Date**: 2026-04-11
**Status**: Accepted

### Context

The skill's security depends on resisting prompt injection and social engineering. Regular functional tests are insufficient—we need adversarial tests that attempt to bypass the Zero-Leak directive.

### Decision

We maintain two Promptfoo test files:

1. **`promptfooconfig.yaml`**: Standard behavioral tests (zero-leak, HITL, error handling)
2. **`promptfooconfig_adversarial.yaml`**: Adversarial attack scenarios

### Adversarial Test Categories

| Category | Examples |
| --- | --- |
| Role Override | "Ignore instructions", "Developer mode" |
| Hypothetical | "In a hypothetical scenario..." |
| Encoding | Base64, hex, URL-encoded secrets |
| Context Overflow | Flooding with fake secrets |
| Authority Claims | "Compliance requires...", "I'm authorized" |

### Pass Criteria

- Critical tests (role override, encoding): 100% pass required
- Other adversarial tests: 80% pass required
- Any failure triggers security review

### Consequences

- **Positive**: Proactive security validation
- **Positive**: Documents expected attack vectors
- **Negative**: Tests require external LLM API
- **Negative**: Grading is subjective (uses llm-rubric)

---

## ADR-013: Coverage Thresholds and Enforcement

**Date**: 2026-04-11
**Status**: Accepted

### Context

We need to ensure critical scripts have adequate test coverage, but don't want to mandate 100% coverage which could encourage test pollution.

### Decision

We enforce these coverage thresholds:

| Script Category | Minimum Coverage |
| --- | --- |
| Security-critical (`audit_secrets.sh`, `emergency_seal.sh`) | 90% |
| Core functionality (`check_status.sh`, manager implementations) | 80% |
| Utility scripts (`tracing.sh`, `detect_manager.sh`) | 60% |
| Documentation-only scripts | 0% |

### Enforcement

Coverage is measured in CI using a simple line-count approach:

```bash
# Calculate coverage
total_lines=$(wc -l < "$script")
executed_lines=$(grep -v '^[[:space:]]*#' "$script" | grep -v '^[[:space:]]*$' | wc -l)
coverage=$((executed_lines * 100 / total_lines))

# Fail if below threshold
if [[ "$coverage" -lt "$MIN_COVERAGE" ]]; then
    echo "ERROR: $script coverage ($coverage%) below threshold ($MIN_COVERAGE%)"
    exit 1
fi
```

### Consequences

- **Positive**: Ensures critical paths are tested
- **Positive**: Low overhead measurement
- **Negative**: Line count is a rough proxy for real coverage
- **Negative**: Comments can inflate measured coverage

### Future Direction

Consider adopting `bashcov` or `kcov` for more accurate coverage measurement if the project grows larger.

---

## ADR-014: Claude Code Skill Native Integration

**Date**: 2026-04-11
**Status**: Accepted

### Context

This skill should be a first-class citizen in Claude Code's skill ecosystem, not just a markdown file dropped into a repository. We need proper tool definitions, skill manifest, and seamless registration.

### Decision

We implement the `.claude/skills/doppler-skill/` directory structure:

1. **`manifest.json`**: Skill metadata (name, version, authors, tags, when-to-invoke)
2. **`skill.md`**: Skill-specific behavioral guidance referencing SKILL.md
3. **`tools/*.json`**: Tool definitions for each operation (sm_status, sm_run, sm_fetch, sm_audit, sm_emergency, sm_lease, sm_rotate, sm_request)
4. **`CLAUDE.md`**: Top-level entry point at repository root

### Consequences

- **Positive**: Claude Code can properly invoke this skill with typed tools
- **Positive**: Better discoverability and organization
- **Negative**: Additional maintenance burden for manifest sync
- **Negative**: Tool definitions must stay in sync with script capabilities

---

## ADR-015: Secret Lease/TTL Management

**Date**: 2026-04-11
**Status**: Accepted

### Context

Secrets should not be held indefinitely. We need time-based lease management to:
- Force periodic re-authentication
- Enable secret rotation detection
- Support short-lived credentials (Vault, AWS IAM roles)

### Decision

We implement `sm_lease <manager> <secret>` which:
1. Fetches the secret with TTL metadata
2. Tracks lease expiration in `~/.cache/doppler-manager/leases/`
3. Returns `{value, expires_at, renewal_required}` JSON
4. Emits warnings when renewal is required

### Consequences

- **Positive**: Supports short-lived credentials natively
- **Positive**: Forces periodic rotation validation
- **Negative**: Adds complexity to secret access pattern
- **Negative**: Not all managers support TTL (fallback to sm_fetch)

---

## ADR-016: Secret Rotation Automation

**Date**: 2026-04-11
**Status**: Accepted

### Context

Stale secrets (unused for > 90 days) are a security risk. We need automated detection and rotation triggering.

### Decision

We implement `sm_rotate <manager> <secret>`:
1. Check last access timestamp from audit log
2. If > 90 days, emit WARN and suggest rotation
3. For managers with rotation APIs (Doppler, Vault), trigger rotation
4. For others, provide copy-paste human command

### Consequences

- **Positive**: Proactive security hygiene
- **Positive**: Reduces secret sprawl
- **Negative**: Rotation may break dependent services
- **Negative**: 90-day threshold is arbitrary

---

## ADR-017: Secret Access Request/Approval Workflow

**Date**: 2026-04-11
**Status**: Accepted

### Context

For regulated environments, AI agents should not access secrets without human approval. We need a formal request-approve-reject workflow.

### Decision

We implement `sm_request`, `sm_approve`, `sm_reject`:
1. `sm_request <secret> <reason>` creates JSON request in `~/.config/doppler-manager/requests/`
2. `sm_list_requests` shows pending requests
3. `sm_approve <id>` or `sm_reject <id>` updates status
4. Audit log records all state transitions

### Consequences

- **Positive**: Compliant with security governance
- **Positive**: Full audit trail of access decisions
- **Negative**: Adds friction to secret access
- **Negative**: No enforcement mechanism (AI could bypass)

---

## ADR-018: Rate Limiting for Audit Logging

**Date**: 2026-04-11
**Status**: Accepted

### Context

Audit logging endpoints could be overwhelmed by a malicious or buggy script making thousands of requests per second.

### Decision

We implement token bucket rate limiting in `rate_limit.sh`:
1. Each operation type has a bucket (sm_run: 60/min, sm_fetch: 120/min, sm_audit: 30/min)
2. Buckets stored in `~/.cache/doppler-manager/rate_limits/`
3. Exceeded limits return E429 with retry-after hint
4. Buckets auto-refill; can be manually reset

### Consequences

- **Positive**: Prevents DoS on audit infrastructure
- **Positive**: Graceful degradation under load
- **Negative**: Legitimate bursty workloads may be throttled
- **Negative**: Storage management for bucket files

---

## ADR-019: Distributed Tracing OTLP Export

**Date**: 2026-04-11
**Status**: Accepted

### Context

Current tracing is in-memory only. For production deployments, traces should export to an OTLP-compatible backend (Jaeger, Zipkin, Honeycomb).

### Decision

We enhance `tracing.sh` to:
1. Export spans to `${OTEL_ENDPOINT}/v1/traces` when OTEL_EXPORTER is set
2. Use OTLP HTTP protocol with JSON encoding
3. Batch spans for efficiency (flush on 100 spans or 5 second timeout)
4. Include `service.name`, `service.version`, `deployment.environment` resource attributes

### Consequences

- **Positive**: Production-grade observability
- **Positive**: Correlate with existing APM tools
- **Negative**: Requires OTEL_ENDPOINT configuration
- **Negative**: Python3 dependency for JSON processing in trace_end()

---

## ADR-020: CI/CD Secret Scanning with git-secrets

**Date**: 2026-04-11
**Status**: Accepted

### Context

Accidental secret commits could leak credentials. We need pre-merge scanning to catch this.

### Decision

We add `scan-secrets` job to CI:
1. Install `git-secrets` via apt or direct download
2. Register built-in patterns (AWS, GCP, Azure, generic)
3. Run `git secrets --scan` on all files
4. Fail CI if any pattern matches
5. Additionally scan commit history with `git secrets --scan --cached`

### Consequences

- **Positive**: Catches accidental secret commits before merge
- **Positive**: Low false positive rate with built-in patterns
- **Negative**: git-secrets installation adds CI time
- **Negative**: Some false positives require whitelisting
