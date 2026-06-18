# Local Mac Qwen/Ollama Linux gh-aw runner

This helper prepares the Linux self-hosted runner needed by `.github/workflows/local-macrunner-qwenollama.md`.

The macOS runner can smoke-test local Ollama directly, but the `gh-aw` agent job itself needs Linux, Docker, passwordless sudo, and iptables. Run this helper inside the Linux VM or Linux host that should execute the agent job.

## Smallest Model Default

The local agent lane defaults to:

```text
qwen2.5:0.5b
```

That is intentionally tiny for smoke-testing the plumbing. It is not expected to be a strong coding agent; it is the lightest Qwen model this demo uses to prove the end-to-end local path.

## Mac Side

On the Mac, make sure Ollama is running and reachable from the Linux VM. For a VM or nearby Linux host, expose Ollama deliberately:

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
- Uses `qwen2.5:0.5b` by default.
- Creates an `actions` user with passwordless sudo.
- Sets repository variables for the local agent endpoint and tiny Qwen model.
- Registers a GitHub Actions runner with `local-macrunner-qwenollama,gh-aw`.
- Starts a local proxy from `127.0.0.1:8080` to the Mac-hosted Ollama endpoint.
- Adds `host.docker.internal` on the Linux host so the workflow pre-step and `gh-aw` container both use `http://host.docker.internal:8080/v1`.

Useful overrides:

```bash
LOCAL_AGENT_MODEL=qwen2.5:0.5b infra/local-macrunner-qwenollama/setup-linux-runner.sh
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

After the runner is already set up, the same command can be run from any machine with `gh` access:

```bash
scripts/run-local-macrunner-qwenollama.sh
```

When run on Linux, the script starts or registers the runner before dispatching the workflow. When run on macOS or another machine, it verifies that a matching Linux runner is already online before dispatching.

Useful run overrides:

```bash
scripts/run-local-macrunner-qwenollama.sh "Check the local agent lane."
REF=main WATCH=0 scripts/run-local-macrunner-qwenollama.sh
SETUP_RUNNER=0 WAIT_FOR_RUNNER=0 scripts/run-local-macrunner-qwenollama.sh
DRY_RUN=1 scripts/run-local-macrunner-qwenollama.sh
```
