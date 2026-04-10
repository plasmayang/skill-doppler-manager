# Doppler Standard Operating Procedure (SOP)

This document serves as a guide for both human operators and the AI agent for bootstrapping and configuring the Doppler CLI environment.

## Phase 1: Installation

Determine the host operating system and execute the corresponding installation commands.

### Debian / Ubuntu

```bash
# Update and install dependencies
sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gnupg

# Add Doppler GPG key and APT repository
curl -sLf --retry 3 --tlsv1.2 --proto "=https" 'https://packages.doppler.com/public/cli/gpg.DE2A7741A397C129.key' | sudo gpg --dearmor -o /usr/share/keyrings/doppler-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/doppler-archive-keyring.gpg] https://packages.doppler.com/public/cli/deb/debian any-version main" | sudo tee /etc/apt/sources.list.d/doppler-cli.list

# Install CLI
sudo apt-get update && sudo apt-get install doppler
```

### macOS (Homebrew)

```bash
brew install dopplerhq/cli/doppler
```

### Windows (Scoop)

```powershell
scoop bucket add doppler https://github.com/DopplerHQ/scoop-doppler.git
scoop install doppler
```

## Phase 2: Authentication

Once installed, the CLI must be authenticated to access the cloud workspace.

### Option A: Interactive Developer Login (Recommended for Local Dev)

For personal workstations and Codespaces, use the interactive web login.

1. Run `doppler login` in the terminal.
2. Follow the prompt to open the browser and authorize the device.
3. Once authenticated, navigate to your project directory and run `doppler setup` to link the directory to a specific Doppler Project and Configuration.

### Option B: Service Token (For CI/CD or Headless Servers)

For servers or automated environments where interactive login is impossible, use a Service Token.

1. Generate a Service Token via the Doppler Web UI for the specific Project and Config.
2. Configure the CLI using the token:

   ```bash
   doppler configure set token dp.st.xxxxxx
   ```

## Phase 3: Verification

Verify the setup by attempting to read secrets.
*Note: AI Agents should rely on `scripts/check_status.sh` rather than running this manually, as it prevents secrets from entering the context window.*

```bash
# Verify authentication status
doppler configure

# Test fetching secrets (Human only, AI should avoid to prevent leaks)
doppler secrets
```
