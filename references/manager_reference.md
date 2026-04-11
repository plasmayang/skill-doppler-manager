# Secret Manager Reference

This document provides a comprehensive command reference for all supported secret managers.

## Supported Secret Managers

| Manager | Priority | CLI | Token Format |
|---------|----------|-----|--------------|
| Doppler | 100 | `doppler` | `dp.st.xxxxxx` (service), `dp.pt.xxxxxx` (personal) |
| Infisical | 70 | `infisical` or `fi` | `ip.st.xxxxxx` (service), `ip.pt.xxxxxx` (personal) |
| HashiCorp Vault | 80 | `vault` | Vault tokens, AWS IAM, Kubernetes |
| AWS Secrets Manager | 60 | `aws secretsmanager` | IAM credentials |
| GCP Secret Manager | 40 | `gcloud secrets` | GCP service accounts |
| Azure Key Vault | 30 | `az keyvault` | Azure AD tokens |

---

## Doppler CLI

### Installation

**macOS:**
```bash
brew install dopplerhq/cli/doppler
```

**Linux:**
```bash
curl -sLf --retry 3 --tlsv1.2 --proto '=https' 'https://packages.doppler.com/public/cli/gpg.DE2A7741A397C129.key' | sudo gpg --dearmor -o /usr/share/keyrings/doppler-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/doppler-archive-keyring.gpg] https://packages.doppler.com/public/cli/deb/debian any-version main" | sudo tee /etc/apt/sources.list.d/doppler-cli.list
sudo apt-get update && sudo apt-get install doppler
```

**Windows (Scoop):**
```powershell
scoop bucket add doppler https://github.com/DopplerHQ/scoop-doppler.git
scoop install doppler
```

### Authentication

**Interactive (User Token):**
```bash
doppler login
```

**Service Token (CI/Headless):**
```bash
doppler configure set token dp.st.xxxxxx
```

### Key Commands

| Operation | Command |
|-----------|---------|
| Check status | `doppler configure` |
| Get project | `doppler configure get project --plain` |
| Get config | `doppler configure get config --plain` |
| Run with secrets | `doppler run -- <command>` |
| Get secret | `doppler secrets get <KEY> --plain` |
| Set secret (HITL) | `doppler secrets set <KEY>=<value>` |

### Interface Functions

```bash
source scripts/secret_manager_interface.sh
sm_load doppler
sm_status           # JSON status
sm_run <cmd>        # Inject and run
sm_get <key>        # Get secret (memory-only)
sm_set <key>       # Output HITL command
```

---

## Infisical CLI

### Installation

**macOS:**
```bash
brew install infisical-infisical/infisical/mac-cli
```

**Linux:**
```bash
curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical/setup.linux.sh' | bash
apt-get install -y infisical
```

**npm:**
```bash
npm install -g @infisical/infisical
```

### Authentication

**Interactive:**
```bash
infisical login
# or
fi login
```

**Service Token:**
```bash
infisical config set-token ip.st.xxxxxx
# or
fi config set-token ip.st.xxxxxx
```

### Key Commands

| Operation | Command |
|-----------|---------|
| Check status | `infisical secrets list --limit 1` |
| Get project | `infisical config view --field=project_path` |
| Get environment | `infisical config view --field=environment` |
| Run with secrets | `infisical run -- <command>` |
| Get secret | `infisical secrets get <KEY> --plain` |
| Set secret (HITL) | `infisical secrets set <KEY>=<value>` |

### Interface Functions

```bash
source scripts/secret_manager_interface.sh
sm_load infisical
sm_status           # JSON status
sm_run <cmd>        # Inject and run
sm_get <key>        # Get secret (memory-only)
sm_set <key>       # Output HITL command
```

---

## HashiCorp Vault

### Installation

See: https://developer.hashicorp.com/vault/install

### Authentication

```bash
vault login <token>
# or
vault auth aws login          # AWS IAM
vault auth kubernetes login   # Kubernetes
```

### Key Commands

| Operation | Command |
|-----------|---------|
| Check status | `vault status` |
| Get secret | `vault kv get -format=json <path>` |
| Set secret (HITL) | `vault kv put <path> <key>=<value>` |
| List secrets | `vault kv list <path>` |

### Interface Functions

```bash
source scripts/secret_manager_interface.sh
sm_load vault
sm_status           # JSON status
sm_run <cmd>       # Run with env vars
sm_get <path>      # Get secret (first value)
sm_set <path>      # Output HITL command
```

**Note:** Vault secrets require a secret path (e.g., `secret/data/myapp`).

---

## AWS Secrets Manager

### Installation

```bash
# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# macOS
brew install awscli
```

### Authentication

```bash
aws configure
# or
export AWS_ACCESS_KEY_ID=xxx
export AWS_SECRET_ACCESS_KEY=xxx
export AWS_DEFAULT_REGION=us-east-1
```

### Key Commands

| Operation | Command |
|-----------|---------|
| List secrets | `aws secretsmanager list-secrets` |
| Get secret | `aws secretsmanager get-secret-value --secret-id <name>` |
| Set secret (HITL) | `aws secretsmanager put-secret-value --secret-id <name> --secret-string <value>` |

### Interface Functions

```bash
source scripts/secret_manager_interface.sh
sm_load aws_secrets
sm_status           # JSON status
sm_run <cmd>        # Run with AWS env
sm_get <name>       # Get secret value
sm_set <name>       # Output HITL command
```

---

## GCP Secret Manager

### Installation

```bash
# Linux
curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/google-cloud-sdk.tar.gz
tar -xf google-cloud-sdk.tar.gz
./google-cloud-sdk/install.sh

# macOS
brew install google-cloud-sdk
```

### Authentication

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project <project-id>
```

### Key Commands

| Operation | Command |
|-----------|---------|
| List secrets | `gcloud secrets list` |
| Get secret | `gcloud secrets versions access latest --secret=<name>` |
| Set secret (HITL) | `echo -n <value> \| gcloud secrets create <name> --data-file=-` |

### Interface Functions

```bash
source scripts/secret_manager_interface.sh
sm_load gcp_secret
sm_status           # JSON status
sm_run <cmd>        # Run with GCP env
sm_get <name>       # Get secret value
sm_set <name>       # Output HITL command
```

**Note:** Set `GCP_PROJECT_ID` environment variable or configure default project.

---

## Azure Key Vault

### Installation

```bash
# Linux
curl -sL https://aka.ms/InstallAzureCLILinux | bash

# macOS
brew install azure-cli
```

### Authentication

```bash
az login
az account set --subscription <subscription-id>
```

### Key Commands

| Operation | Command |
|-----------|---------|
| List vaults | `az keyvault list` |
| Get secret | `az keyvault secret show --vault-name <vault> --name <name>` |
| Set secret (HITL) | `az keyvault secret set --vault-name <vault> --name <name> --value <value>` |

### Interface Functions

```bash
source scripts/secret_manager_interface.sh
sm_load azure_key
sm_status           # JSON status
sm_run <cmd>        # Run with Azure env
sm_get <vault/name> # Get secret value
sm_set <vault/name> # Output HITL command
```

**Note:** Secret reference format is `vault-name/secret-name`.

---

## Multi-Manager Usage

### Auto-Detection

```bash
# Detect all available managers
bash scripts/detect_manager.sh

# Output as JSON
bash scripts/detect_manager.sh --json

# Auto-select best manager
bash scripts/detect_manager.sh --select
```

### Programmatic Usage

```bash
# Source the interface
source scripts/secret_manager_interface.sh

# Auto-detect and load best manager
sm_detect_managers

# Or load a specific manager
sm_load doppler

# Check if configured
if sm_is_configured; then
    echo "Ready to use $CURRENT_MANAGER"
fi

# Run commands with secrets
sm_run python3 app.py

# Get individual secrets
API_KEY=$(sm_get API_KEY)
```

### Status JSON Format

All managers return status in this format:

```json
{
  "status": "OK|WARNING|ERROR",
  "code": "E000|E001|...",
  "message": "Human-readable message",
  "hint": "Recovery action",
  "documentation": "references/SOP.md#section",
  "project": "project-name",
  "config": "config-name",
  "manager": "manager-name"
}
```

---

## Error Codes

| Code | Manager | Meaning |
|------|---------|---------|
| E000 | All | Authenticated and configured |
| E001 | All | CLI not installed |
| E002 | All | Not authenticated |
| E003 | Doppler | Token expired |
| E004 | All | No project/config set |
| E005 | Doppler | Permission denied |
| E006 | All | Network error |
| E007 | Doppler | Config mismatch |
| E100 | Interface | Manager not supported |
| E101 | Interface | Manager not configured |
| E102 | Interface | Manager-specific error |
