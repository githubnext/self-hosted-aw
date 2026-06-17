---
description: "Run a gh-aw agent on a Linux self-hosted runner wired to a local Mac-hosted Qwen/Ollama endpoint."
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
runs-on-slim: ubuntu-latest
timeout-minutes: 30

engine:
  id: copilot
  env:
    COPILOT_PROVIDER_BASE_URL: "http://host.docker.internal:11434/v1"
    COPILOT_MODEL: "qwen3.6:27b"
    COPILOT_PROVIDER_TYPE: "openai"
    COPILOT_PROVIDER_WIRE_API: "completions"
    COPILOT_PROVIDER_MAX_PROMPT_TOKENS: "12000"
    COPILOT_PROVIDER_MAX_OUTPUT_TOKENS: "1200"

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
      LOCAL_OPENAI_BASE_URL: "http://host.docker.internal:11434/v1"
      LOCAL_OPENAI_MODEL: "qwen3.6:27b"
      LOCAL_OPENAI_API_KEY: "ollama"
    run: bash scripts/smoke-local-openai-compatible.sh

---

# Local Mac Runner Qwen/Ollama Agent

You are running inside a GitHub Agentic Workflow on a Linux self-hosted runner that is connected to a local Mac-hosted Ollama endpoint.

Goal: demonstrate that this repository can run an agentic workflow while routing inference to a local Qwen model served by Ollama.

Important runtime shape:

1. The `gh-aw` agent job itself must run on Linux with Docker, sudo, and iptables.
2. The local Qwen model is served by Ollama from the nearby Mac.
3. The model endpoint should be reachable at `http://host.docker.internal:11434/v1` from the agent runner environment.

Do the following:

1. Inspect the current workspace and runner context.
2. Read the output or rerun `bash scripts/check-gh-aw-runner.sh` if needed.
3. Confirm the engine configuration is using Copilot BYOK mode with `COPILOT_PROVIDER_BASE_URL=http://host.docker.internal:11434/v1`.
4. Confirm the requested model is `qwen3.6:27b`.
5. Summarize whether the local Mac Qwen/Ollama lane is suitable for `gh-aw` agent workloads.
6. Do not modify repository files.

Optional user instruction:

`${{ github.event.inputs.prompt }}`
