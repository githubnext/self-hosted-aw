# macOS local model runner lane

This lane registers any macOS machine as a self-hosted GitHub Actions runner and smoke-tests an OpenAI-compatible local model endpoint.

This is not a `gh-aw` runner lane. The `gh-aw` lanes still require Linux, Docker, sudo, and iptables. This macOS lane is for regular GitHub Actions jobs that run on a Mac and call a local model endpoint.

For a true Agentic Workflow backed by the Mac's Ollama model, use `.github/workflows/local-macrunner-qwenollama.md`. That workflow still needs a Linux `gh-aw` runner, but the model provider is the Mac-hosted Ollama endpoint. The smallest end-to-end helper for that lane is `infra/local-macrunner-qwenollama/setup-tiny-qwen-agent.sh`.

## Routing Contract

The workflow targets these labels:

```text
self-hosted,macOS,macos-local,local-model
```

GitHub adds the default `self-hosted`, `macOS`, and architecture labels during runner registration. The helper adds the custom labels:

```text
macos-local,local-model
```

Any Mac with those labels can run `.github/workflows/macos-local-model-smoke.yml`.

For a Mac that hosts the default tiny Qwen model, add a model label too:

```text
qwen2-5-0-5b
```

That label lets `.github/workflows/macos-qwen-local-model-smoke.yml` route only to a machine that has the expected Qwen model installed.

The full Agentic Workflow lane uses these Linux runner labels instead:

```text
self-hosted,linux,x64,local-macrunner-qwenollama,gh-aw
```

## Recommended Security Shape

Use a private repository and a dedicated macOS user account for the runner. A self-hosted runner can execute workflow code on the machine, so do not attach a personal daily-driver account to untrusted workflows.

For a borrowed or remote Mac, prefer:

```text
Tailscale for admin access
GitHub runner for job scheduling
local model server bound to 127.0.0.1
```

Tailscale is not how GitHub finds the runner. The runner connects outbound to GitHub. Tailscale is useful for SSH/admin access to the Mac and for reaching private tailnet resources from jobs.

## Local Model Endpoint

The default endpoint is Ollama's OpenAI-compatible API:

```text
http://127.0.0.1:11434/v1
```

Install Ollama, start it, and pull a model:

```bash
ollama pull qwen2.5:0.5b
ollama cp qwen2.5:0.5b qwen2.5-0.5b
ollama cp qwen2.5-0.5b openai/qwen2.5-0.5b
```

Set repository variables for another OpenAI-compatible local server:

```bash
gh variable set LOCAL_OPENAI_BASE_URL --body "http://127.0.0.1:11434/v1"
gh variable set LOCAL_OPENAI_MODEL --body "openai/qwen2.5-0.5b"
```

If the local server requires an API key, set:

```bash
gh secret set LOCAL_OPENAI_API_KEY
```

Ollama ignores the API key value for its OpenAI-compatible endpoint, so no secret is needed for the default setup.

## One-command Qwen Setup

On the Mac that will host Ollama and the macOS self-hosted runner, run:

```bash
infra/macos/setup-local-qwen-ollama.sh
```

The setup helper:

- Installs `gh` and `ollama` with Homebrew if they are missing.
- Starts Ollama.
- Pulls `qwen2.5:0.5b`.
- Creates both `qwen2.5-0.5b` and `openai/qwen2.5-0.5b` aliases for the pulled Qwen model.
- Smoke-tests Ollama's OpenAI-compatible endpoint.
- Sets the repository variables used by the local model workflows.
- Registers the macOS runner with `macos-local,local-model,qwen2-5-0-5b`.
- Installs the GitHub runner as a background service by default.

By default, the runner name is:

```text
  <mac-hostname>-qwen2-5-0-5b
```

Useful overrides:

```bash
QWEN_OLLAMA_MODEL=qwen2.5:0.5b infra/macos/setup-local-qwen-ollama.sh
QWEN_OLLAMA_MODEL_ALIAS=qwen2.5-0.5b infra/macos/setup-local-qwen-ollama.sh
QWEN_OLLAMA_PROVIDER_ALIAS=openai/qwen2.5-0.5b infra/macos/setup-local-qwen-ollama.sh
REGISTER_MACOS_RUNNER=0 infra/macos/setup-local-qwen-ollama.sh
INSTALL_RUNNER_SERVICE=0 infra/macos/setup-local-qwen-ollama.sh
SET_GITHUB_VARIABLES=0 infra/macos/setup-local-qwen-ollama.sh
RUN_SMOKE=0 infra/macos/setup-local-qwen-ollama.sh
RESTART_OLLAMA=0 infra/macos/setup-local-qwen-ollama.sh
PULL_MODEL=0 infra/macos/setup-local-qwen-ollama.sh
INSTALL_HOMEBREW=1 infra/macos/setup-local-qwen-ollama.sh
INSTALL_TAILSCALE=1 infra/macos/setup-local-qwen-ollama.sh
```

If a nearby Linux `gh-aw` runner needs to call Ollama over the network, expose Ollama deliberately:

```bash
EXPOSE_OLLAMA_TO_NETWORK=1 infra/macos/setup-local-qwen-ollama.sh
```

That binds Ollama to `0.0.0.0:11434` by setting `OLLAMA_HOST` with `launchctl`. Use this only on a trusted network or tailnet.

## Register A Local Mac

From this repository on the Mac:

```bash
infra/macos/register-runner.sh
```

By default the helper derives a runner name from the Mac hostname:

```text
<mac-hostname>-local-model
```

Start the runner interactively:

```bash
cd "$HOME/actions-runner-<mac-hostname>-local-model"
./run.sh
```

Install it as a background service instead:

```bash
INSTALL_RUNNER_SERVICE=1 infra/macos/register-runner.sh
```

Use a custom config for a specific Mac:

```bash
cp infra/macos/runner.conf infra/macos/runner.local.conf
MACOS_RUNNER_CONFIG=infra/macos/runner.local.conf infra/macos/register-runner.sh
```

`infra/macos/*.local.conf` is ignored by git.

Example config for a Qwen-capable Mac:

```bash
cat > infra/macos/runner.local.conf <<'EOF'
: "${RUNNER_VERSION:=2.329.0}"
: "${RUNNER_NAME:=qwen3-27b-macos-01}"
: "${RUNNER_LABELS:=macos-local,local-model,qwen3-27b}"
: "${RUNNER_DIR:=${HOME}/actions-runner-${RUNNER_NAME}}"
: "${INSTALL_RUNNER_SERVICE:=1}"
EOF

MACOS_RUNNER_CONFIG=infra/macos/runner.local.conf infra/macos/register-runner.sh
```

## Register A Remote Mac Over Tailscale

On the remote Mac:

1. Install and log in to Tailscale.
2. Enable SSH access by using normal macOS Remote Login or Tailscale SSH.
3. Install `gh` and authenticate with a GitHub account that can administer this repository.
4. Clone this repository.
5. Install and start the local model server, such as Ollama.
6. Run the registration helper.

From your workstation:

```bash
ssh user@remote-mac
cd ~/github/self-hosted-aw
infra/macos/register-runner.sh
cd "$HOME/actions-runner-$(scutil --get LocalHostName | tr '[:upper:]' '[:lower:]')-local-model"
./run.sh
```

For a persistent remote runner:

```bash
INSTALL_RUNNER_SERVICE=1 infra/macos/register-runner.sh
```

If the remote Mac should access other tailnet-only services during a job, make sure the Tailscale ACL grants that Mac access. The workflow itself does not need a Tailscale GitHub Action step when the runner host is already in the tailnet.

## Run The Smoke Test

```bash
gh workflow run macos-local-model-smoke.yml
gh workflow run macos-qwen-local-model-smoke.yml
```

The smoke test checks:

```text
macOS host
curl and git
optional Tailscale status
local OpenAI-compatible /models endpoint
outbound access to GitHub
chat completion through the local model endpoint
```

## Remove The Runner

From the same Mac:

```bash
infra/macos/remove-runner.sh
```

The helper removes the GitHub runner registration and stops/uninstalls the service if present. The runner directory is left on disk so you can inspect or delete it manually.
