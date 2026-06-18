---
description: "Run a gh-aw agent on a local Mac-hosted Linux runner VM wired to the Mac's Qwen/Ollama endpoint."
labels: ["demo", "self-hosted", "local", "mac", "qwen", "ollama"]

on:
  workflow_dispatch:
    inputs:
      prompt:
        description: "Optional extra instruction for the agent"
        required: false
        default: "Confirm whether the local Mac Qwen/Ollama lane is ready for agentic workflows."

permissions:
  contents: read
  actions: read

runs-on: [self-hosted, linux, x64, local-macrunner-qwenollama, gh-aw]
runs-on-slim: local-macrunner-qwenollama
timeout-minutes: 30

engine:
  id: codex
  model: openai/qwen2.5-0.5b
  env:
    OPENAI_BASE_URL: "http://host.docker.internal:11435/v1"
    OPENAI_API_KEY: "${{ secrets.LOCAL_AGENT_OPENAI_API_KEY || 'ollama' }}"

models:
  providers:
    openai:
      models:
        qwen2.5-0.5b:
          cost:
            input: "1e-09"
            output: "1e-09"
            cache_read: "1e-09"

network:
  allowed:
    - defaults
    - host.docker.internal

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
  - name: Smoke test local Qwen/Ollama endpoint
    env:
      LOCAL_OPENAI_BASE_URL: "${{ vars.LOCAL_AGENT_OPENAI_BASE_URL || 'http://host.docker.internal:11435/v1' }}"
      LOCAL_OPENAI_MODEL: "${{ vars.LOCAL_AGENT_OPENAI_MODEL || 'qwen2.5-0.5b' }}"
      LOCAL_OPENAI_API_KEY: "ollama"
    run: bash scripts/smoke-local-openai-compatible.sh

---

# Local Mac Runner Qwen/Ollama Agent

You are running inside a GitHub Agentic Workflow on a Linux self-hosted runner VM hosted by the same local Mac that serves the Ollama endpoint.

Goal: demonstrate that this repository can run an agentic workflow while routing inference to a local Qwen model served by Ollama.

Important runtime shape:

1. The `gh-aw` agent job itself runs in a local x86_64 Linux VM with Docker, sudo, and iptables.
2. The local Qwen model is served by Ollama on the Mac host.
3. The model endpoint is proxied through the VM and should be reachable at `http://host.docker.internal:11435/v1` from the agent runner environment.
4. The workflow-safe model alias is `qwen2.5-0.5b`, backed by the Ollama source model `qwen2.5:0.5b`.

Do the following:

1. Inspect the current workspace and runner context.
2. Read the output or rerun `bash scripts/check-gh-aw-runner.sh` if needed.
3. Confirm the engine configuration is using the Codex engine with `OPENAI_BASE_URL` pointing at the local runner proxy.
4. Confirm the requested model is the configured tiny Qwen model alias, defaulting to `openai/qwen2.5-0.5b` in the workflow and `qwen2.5-0.5b` on the Ollama wire.
5. Summarize whether the local Mac Qwen/Ollama lane is suitable for `gh-aw` agent workloads.
6. Do not modify repository files.

Optional user instruction:

`${{ github.event.inputs.prompt }}`
