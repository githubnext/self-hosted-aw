# gh-aw self-hosted runner and OpenRouter demonstrator

This repository demonstrates GitHub Agentic Workflows running on self-hosted GitHub Actions runners and using an OpenAI-compatible inference provider through OpenRouter.

The repo has three demo lanes:

- Azure VM runner: a `gh-aw` workflow routed to `[self-hosted, linux, x64, azure]`.
- Cloudflare runner lane: a `gh-aw` workflow routed to `[self-hosted, linux, x64, cloudflare]`, with an explicit capability check for Docker, sudo, iptables, and egress.
- OpenRouter inference: Codex is configured with `OPENAI_BASE_URL=https://openrouter.ai/api/v1` and `OPENAI_API_KEY=${{ secrets.OPENROUTER_API_KEY }}`.

## Repository Map

- `.github/workflows/azure-vm-openrouter.md` - agentic workflow for an Azure-hosted runner.
- `.github/workflows/cloudflare-runner-openrouter.md` - agentic workflow for a Cloudflare-labeled runner lane.
- `.github/workflows/runner-capability-smoke.yml` - deterministic GitHub Actions smoke test for runner labels and OpenRouter.
- `scripts/check-gh-aw-runner.sh` - validates the self-hosted runner requirements needed by `gh-aw`.
- `scripts/smoke-openrouter.sh` - makes a minimal OpenRouter chat-completions request.
- `infra/azure-vm/` - Azure VM bootstrap helper, config, and cloud-init template.
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

## Runner Labels

Register self-hosted runners with these labels:

```text
self-hosted,linux,x64,azure,gh-aw
self-hosted,linux,x64,cloudflare,gh-aw
```

`gh-aw` self-hosted runners must be Linux hosts with Docker, passwordless sudo for the runner service account, iptables support, and outbound HTTPS access to GitHub, GHCR, the selected engine endpoint, and any domains listed in the workflow network allowlist.

## Compile

Compile the Markdown workflows into generated GitHub Actions lock files:

```bash
gh aw compile --validate --actionlint
```

The generated `.lock.yml` files are committed because they are the executable GitHub Actions workflows.

## Run The Demos

Run the deterministic smoke workflow first:

```bash
gh workflow run runner-capability-smoke.yml -f target=azure
gh workflow run runner-capability-smoke.yml -f target=cloudflare
gh workflow run runner-capability-smoke.yml -f target=all
```

Then run an agentic workflow:

```bash
gh aw run azure-vm-openrouter
gh aw run cloudflare-runner-openrouter
```

The agent will inspect the runner, confirm the provider routing, and summarize whether the lane is ready for agentic workloads.

## Cloudflare Note

Cloudflare Workers and Containers are useful deployment targets, but the `gh-aw` agent job itself needs host-level Docker and sudo/iptables. If a Cloudflare compute environment cannot provide those, use a Linux host reachable through Cloudflare Tunnel or another Cloudflare-managed/private network pattern, register that host as a GitHub Actions runner, and label it `cloudflare`.
