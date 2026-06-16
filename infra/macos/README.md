# macOS local model runner lane

This lane registers any macOS machine as a self-hosted GitHub Actions runner and smoke-tests an OpenAI-compatible local model endpoint.

This is not a `gh-aw` runner lane. The `gh-aw` lanes still require Linux, Docker, sudo, and iptables. This macOS lane is for regular GitHub Actions jobs that run on a Mac and call a local model endpoint.

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
ollama pull llama3.2
```

Set repository variables for another OpenAI-compatible local server:

```bash
gh variable set LOCAL_OPENAI_BASE_URL --body "http://127.0.0.1:11434/v1"
gh variable set LOCAL_OPENAI_MODEL --body "llama3.2"
```

If the local server requires an API key, set:

```bash
gh secret set LOCAL_OPENAI_API_KEY
```

Ollama ignores the API key value for its OpenAI-compatible endpoint, so no secret is needed for the default setup.

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
