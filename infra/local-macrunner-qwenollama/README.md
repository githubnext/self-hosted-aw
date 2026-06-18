# All-local Mac Qwen/Ollama gh-aw runner

This helper prepares the Linux self-hosted runner needed by `.github/workflows/local-macrunner-qwenollama.md`.

The macOS host serves Qwen through Ollama and also hosts the `gh-aw` runner. Because the `gh-aw` agent job needs Linux, Docker, passwordless sudo, and iptables, the all-local path uses a local x86_64 Lima Linux VM as the GitHub Actions runner while Ollama stays on the Mac host.

## Smallest Model Default

The local agent lane defaults to:

```text
Ollama source model: qwen2.5:0.5b
Workflow model alias: qwen2.5-0.5b
Codex provider model alias: openai/qwen2.5-0.5b
```

That is intentionally tiny for smoke-testing the plumbing. It is not expected to be a strong coding agent; it is the lightest Qwen model this demo uses to prove the end-to-end local path. The workflow alias exists because AWF model identifiers cannot contain the `:` tag character used by Ollama. The provider-qualified alias matches the Codex model ID used by the compiled workflow.

The agent container calls the local model directly at:

```text
http://host.docker.internal:11435/v1
```

The local lock file is post-compile patched to bypass the AWF API proxy for this lane because AWF v0.27.0 drops the custom local OpenAI target port and tries the default HTTPS port.

## All-Local Mac Path

On the Mac:

```bash
scripts/run-local-macrunner-qwenollama.sh "Check the local agent lane."
```

The launcher:

- Starts or verifies the Mac-hosted Qwen/Ollama endpoint.
- Creates `qwen2.5-0.5b` and `openai/qwen2.5-0.5b` aliases for the local Ollama model.
- Creates or starts a local x86_64 Lima Linux VM named `gh-aw-local-qwen`.
- Runs the Linux runner bootstrap inside that VM.
- Registers the VM with `self-hosted,linux,x64,local-macrunner-qwenollama,gh-aw`.
- Dispatches `.github/workflows/local-macrunner-qwenollama.lock.yml`.
- Watches the run by default.

Useful all-local overrides:

```bash
WATCH=0 scripts/run-local-macrunner-qwenollama.sh
DRY_RUN=1 scripts/run-local-macrunner-qwenollama.sh
LOCAL_AGENT_MODEL=qwen2.5:0.5b scripts/run-local-macrunner-qwenollama.sh
LOCAL_AGENT_MODEL_ALIAS=qwen2.5-0.5b scripts/run-local-macrunner-qwenollama.sh
LOCAL_AGENT_PROVIDER_MODEL_ALIAS=openai/qwen2.5-0.5b scripts/run-local-macrunner-qwenollama.sh
LIMA_INSTANCE=my-gh-aw-runner scripts/run-local-macrunner-qwenollama.sh
```

## Mac Endpoint Only

On the Mac, make sure Ollama is running and reachable from the local Lima Linux VM. If you are using a separate Linux host instead of the default local VM, expose Ollama deliberately:

```bash
EXPOSE_OLLAMA_TO_NETWORK=1 \
infra/local-macrunner-qwenollama/setup-tiny-qwen-agent.sh
```

Without `EXPOSE_OLLAMA_TO_NETWORK=1`, the helper still installs and smoke-tests the tiny model, but keeps the endpoint bound to localhost.

## Linux Side

Inside the Linux VM or host:

```bash
GITHUB_REPOSITORY=githubnext/self-hosted-aw \
OLLAMA_UPSTREAM_BASE_URL=http://MAC_HOST_OR_IP:11434/v1 \
infra/local-macrunner-qwenollama/setup-tiny-qwen-agent.sh
```

The helper:

- Installs Docker, `socat`, `iptables`, `sudo`, `git`, and other runner prerequisites on apt-based Linux.
- Uses `qwen2.5:0.5b` as the Ollama source model, `qwen2.5-0.5b` as the workflow model alias, and `openai/qwen2.5-0.5b` as the Codex provider model alias by default.
- Creates an `actions` user with passwordless sudo.
- Sets repository variables for the local agent endpoint and tiny Qwen model.
- Registers a GitHub Actions runner with `local-macrunner-qwenollama,gh-aw`.
- Starts a local proxy from `127.0.0.1:11435` to the Mac-hosted Ollama endpoint.
- Adds `host.docker.internal` on the Linux host so the workflow pre-step and `gh-aw` container both use `http://host.docker.internal:11435/v1`.

Useful overrides:

```bash
LOCAL_AGENT_MODEL=qwen2.5:0.5b infra/local-macrunner-qwenollama/setup-linux-runner.sh
LOCAL_AGENT_MODEL_ALIAS=qwen2.5-0.5b infra/local-macrunner-qwenollama/setup-linux-runner.sh
LOCAL_AGENT_PROVIDER_MODEL_ALIAS=openai/qwen2.5-0.5b infra/local-macrunner-qwenollama/setup-linux-runner.sh
SET_GITHUB_VARIABLES=0 infra/local-macrunner-qwenollama/setup-linux-runner.sh
INSTALL_PACKAGES=0 infra/local-macrunner-qwenollama/setup-linux-runner.sh
INSTALL_RUNNER_SERVICE=0 infra/local-macrunner-qwenollama/setup-linux-runner.sh
RUNNER_NAME=my-local-agent-runner infra/local-macrunner-qwenollama/setup-linux-runner.sh
RUNNER_DIR=/opt/actions-runner-local-agent infra/local-macrunner-qwenollama/setup-linux-runner.sh
```

To set up or start the Linux runner and dispatch the workflow in one command from the Linux host:

```bash
GITHUB_REPOSITORY=githubnext/self-hosted-aw \
OLLAMA_UPSTREAM_BASE_URL=http://MAC_HOST_OR_IP:11434/v1 \
scripts/run-local-macrunner-qwenollama.sh
```

After the runner is already set up, the launcher can also be run from any machine with `gh` access:

```bash
scripts/run-local-macrunner-qwenollama.sh
```

When run on Linux, the script starts or registers the runner before dispatching the workflow. When run on macOS, it uses a local Lima VM for the Linux runner. Set `SETUP_RUNNER=0` to only verify an existing runner and dispatch.

Useful run overrides:

```bash
scripts/run-local-macrunner-qwenollama.sh "Check the local agent lane."
REF=main WATCH=0 scripts/run-local-macrunner-qwenollama.sh
SETUP_RUNNER=0 WAIT_FOR_RUNNER=0 scripts/run-local-macrunner-qwenollama.sh
DRY_RUN=1 scripts/run-local-macrunner-qwenollama.sh
```
