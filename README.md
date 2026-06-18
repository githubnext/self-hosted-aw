# gh-aw self-hosted runner and OpenRouter demonstrator

This repository demonstrates GitHub Agentic Workflows running on self-hosted GitHub Actions runners and using OpenAI-compatible inference providers through OpenRouter or local Ollama.

The repo has five demo lanes:

- Azure VM runner: a `gh-aw` workflow routed to `[self-hosted, linux, x64, azure]`.
- Cloudflare runner lane: a `gh-aw` workflow routed to `[self-hosted, linux, x64, cloudflare]`, with an explicit capability check for Docker, sudo, iptables, and egress.
- OpenRouter inference: Codex is configured with `OPENAI_BASE_URL=https://openrouter.ai/api/v1` and `OPENAI_API_KEY=${{ secrets.OPENROUTER_API_KEY }}`.
- Local Mac Qwen/Ollama inference: a `gh-aw` workflow routed to `[self-hosted, linux, x64, local-macrunner-qwenollama]`, with both the Linux runner VM and Ollama endpoint hosted on the same Mac by default.
- macOS local model runner: a regular GitHub Actions workflow routed to `[self-hosted, macOS, macos-local, local-model]` and pointed at a local OpenAI-compatible endpoint such as Ollama.

## Repository Map

- `.github/workflows/azure-vm-openrouter.md` - agentic workflow for an Azure-hosted runner.
- `.github/workflows/local-macrunner-qwenollama.md` - agentic workflow for the all-local Mac lane: Lima Linux runner VM plus Mac-hosted Qwen/Ollama endpoint.
- `.github/workflows/cloudflare-runner-openrouter.md` - agentic workflow for a Cloudflare-labeled runner lane.
- `.github/workflows/azure-runner-capability-smoke.yml` - deterministic smoke test for the Azure runner label lane and OpenRouter.
- `.github/workflows/cloudflare-runner-capability-smoke.yml` - deterministic smoke test for the Cloudflare runner label lane and OpenRouter.
- `.github/workflows/macos-local-model-smoke.yml` - deterministic smoke test for a macOS local-model runner.
- `.github/workflows/macos-qwen-local-model-smoke.yml` - deterministic smoke test pinned to a Qwen-capable macOS runner.
- `scripts/check-gh-aw-runner.sh` - validates the self-hosted runner requirements needed by `gh-aw`.
- `scripts/smoke-openrouter.sh` - makes a minimal OpenRouter chat-completions request.
- `scripts/check-macos-local-runner.sh` - validates the macOS local-model runner lane.
- `scripts/smoke-local-openai-compatible.sh` - makes a minimal local OpenAI-compatible chat-completions request.
- `scripts/check-qwen-only-models.sh` - fails if blocked local model-family identifiers appear in the repo.
- `scripts/run-local-macrunner-qwenollama.sh` - starts or verifies the all-local Mac Qwen/Ollama `gh-aw` runner lane and dispatches the agentic workflow.
- `infra/azure-vm/` - Azure VM bootstrap helper, config, and cloud-init template.
- `infra/local-macrunner-qwenollama/` - Lima/Linux runner bootstrap for the local Mac Qwen/Ollama agentic lane.
- `infra/macos/` - generic macOS runner registration/removal helpers, Qwen/Ollama setup, and local model notes.
- `infra/cloudflare/` - Cloudflare runner notes and constraints.

## Prerequisites

Install the GitHub Agentic Workflows extension:

```bash
gh extension install github/gh-aw
```

Set the OpenRouter key as a repository secret:

```bash
gh aw secrets set OPENROUTER_API_KEY --value "$OPENROUTER_API_KEY"
```

Optionally set a model and attribution metadata for the smoke test:

```bash
gh variable set OPENROUTER_MODEL --body "openai/gpt-4o-mini"
gh variable set OPENROUTER_SITE_URL --body "https://github.com/OWNER/REPO"
gh variable set OPENROUTER_APP_NAME --body "gh-aw-self-hosted-demo"
```

For the all-local Mac path, use the launcher:

```bash
scripts/run-local-macrunner-qwenollama.sh
```

That starts Ollama on the Mac, boots a local x86_64 Lima Linux VM for the `gh-aw` runner, registers that VM with GitHub, dispatches the workflow, and watches the run.
The agent container reaches the Mac-hosted model through the Lima-side bridge at `http://host.docker.internal:11435/v1`.

For only the Mac-hosted Qwen/Ollama model endpoint, use:

```bash
infra/local-macrunner-qwenollama/setup-tiny-qwen-agent.sh
```

For the matching Linux `gh-aw` runner on a separate Linux host instead of the default local Lima VM, run:

```bash
OLLAMA_UPSTREAM_BASE_URL=http://MAC_HOST_OR_IP:11434/v1 infra/local-macrunner-qwenollama/setup-tiny-qwen-agent.sh
```

To start or verify that Linux runner and dispatch the local agent workflow in one command:

```bash
OLLAMA_UPSTREAM_BASE_URL=http://MAC_HOST_OR_IP:11434/v1 scripts/run-local-macrunner-qwenollama.sh
```

## Runner Labels

Register self-hosted runners with these labels:

```text
self-hosted,linux,x64,azure,gh-aw
self-hosted,linux,x64,local-macrunner-qwenollama,gh-aw
self-hosted,linux,x64,cloudflare,gh-aw
self-hosted,macOS,macos-local,local-model
self-hosted,macOS,macos-local,local-model,qwen2-5-0-5b
```

`gh-aw` self-hosted runners must be Linux hosts with Docker, passwordless sudo for the runner service account, iptables support, and outbound HTTPS access to GitHub, GHCR, the selected engine endpoint, and any domains listed in the workflow network allowlist.

## Compile

Compile the Markdown workflows into generated GitHub Actions lock files:

```bash
gh aw compile --validate --actionlint
scripts/patch-local-qwen-awf-pricing.sh
```

The generated `.lock.yml` files are committed because they are the executable GitHub Actions workflows. The local Qwen lane uses a post-compile patch because `gh-aw` currently emits custom local model pricing as workflow metadata, while AWF needs runtime config for unknown local model aliases. The patch also disables the AWF API proxy for the local lane, routes Codex directly to `http://host.docker.internal:11435/v1`, and allows that host port because AWF v0.27.0 drops the custom OpenAI target port when proxying through its API sidecar.

## Run The Demos

Run the deterministic smoke workflow first:

```bash
gh workflow run azure-runner-capability-smoke.yml
gh workflow run cloudflare-runner-capability-smoke.yml
gh workflow run macos-local-model-smoke.yml
gh workflow run macos-qwen-local-model-smoke.yml
```

Then run an agentic workflow:

```bash
gh aw run azure-vm-openrouter
scripts/run-local-macrunner-qwenollama.sh
gh aw run cloudflare-runner-openrouter
```

The agent will inspect the runner, confirm the provider routing, and summarize whether the lane is ready for agentic workloads.

## Cloudflare Note

Cloudflare Workers and Containers are useful deployment targets, but the `gh-aw` agent job itself needs host-level Docker and sudo/iptables. If a Cloudflare compute environment cannot provide those, use a Linux host reachable through Cloudflare Tunnel or another Cloudflare-managed/private network pattern, register that host as a GitHub Actions runner, and label it `cloudflare`.
