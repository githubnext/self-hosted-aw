---
description: "Run a gh-aw agent on a Cloudflare-labeled self-hosted runner lane and route Codex inference through OpenRouter."
labels: ["demo", "self-hosted", "cloudflare", "openrouter"]

on:
  workflow_dispatch:
    inputs:
      prompt:
        description: "Optional extra instruction for the agent"
        required: false
        default: "Confirm whether this Cloudflare lane is ready for agentic workflows."

permissions:
  contents: read
  actions: read

runs-on: [self-hosted, linux, x64, cloudflare]
runs-on-slim: ubuntu-latest
timeout-minutes: 30

engine:
  id: codex
  model: openai/gpt-4o-mini
  env:
    OPENAI_BASE_URL: "https://openrouter.ai/api/v1"
    OPENAI_API_KEY: ${{ secrets.OPENROUTER_API_KEY }}

network:
  allowed:
    - defaults
    - openrouter.ai

max-ai-credits: 250
max-turns: 20

tools:
  bash: [":*"]
  github:
    toolsets: [repos]

steps:
  - uses: actions/checkout@v6
    with:
      persist-credentials: false
  - name: Check gh-aw runner prerequisites
    run: bash scripts/check-gh-aw-runner.sh
  - name: Smoke test OpenRouter
    env:
      OPENROUTER_API_KEY: ${{ secrets.OPENROUTER_API_KEY }}
      OPENROUTER_MODEL: ${{ vars.OPENROUTER_MODEL }}
      OPENROUTER_SITE_URL: ${{ vars.OPENROUTER_SITE_URL }}
      OPENROUTER_APP_NAME: ${{ vars.OPENROUTER_APP_NAME }}
    run: bash scripts/smoke-openrouter.sh

---

# Cloudflare Runner OpenRouter Agent

You are running inside a GitHub Agentic Workflow on a Cloudflare-labeled self-hosted runner lane.

Goal: demonstrate that this repository can target a non-GitHub-hosted runner lane while routing Codex inference to OpenRouter through the OpenAI-compatible API.

Do the following:

1. Inspect the current workspace and runner context.
2. Read the output or rerun `bash scripts/check-gh-aw-runner.sh` if needed.
3. Confirm whether this lane is a full `gh-aw` runner host or a network/access pattern using Cloudflare Tunnel around another Linux host.
4. Confirm the engine configuration is using `OPENAI_BASE_URL=https://openrouter.ai/api/v1`.
5. Summarize whether the runner is suitable for `gh-aw` agent workloads.
6. Do not modify repository files.

Optional user instruction:

`${{ github.event.inputs.prompt }}`
