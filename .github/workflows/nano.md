---
description: "Minimal gh-aw workflow that asks local Qwen/Ollama for one string and files it as an issue."
labels: ["demo", "self-hosted", "local", "mac", "qwen", "ollama", "nano"]

on:
  workflow_dispatch:
    inputs:
      prompt:
        description: "Prompt to send to the local model"
        required: false
        default: "Reply with exactly: nano ok"

permissions:
  contents: read
  actions: read
  issues: read
  pull-requests: read

runs-on: [self-hosted, linux, x64, local-macrunner-qwenollama, gh-aw]
runs-on-slim: local-macrunner-qwenollama
timeout-minutes: 15

engine:
  id: opencode
  model: openai/qwen2.5-0.5b
  env:
    OPENAI_API_KEY: "ollama"
    OPENAI_BASE_URL: "http://host.docker.internal:11435/v1"
    OPENCODE_CONFIG_CONTENT: >-
      {"provider":{"openai":{"npm":"@ai-sdk/openai-compatible","name":"Ollama (local)","options":{"baseURL":"http://host.docker.internal:11435/v1","apiKey":"ollama"},"models":{"qwen2.5-0.5b":{"name":"Qwen 2.5 0.5B (local)"}}}},"enabled_providers":["openai"],"model":"openai/qwen2.5-0.5b","small_model":"openai/qwen2.5-0.5b"}

models:
  providers:
    openai:
      models:
        qwen2.5-0.5b:
          cost:
            input: "1e-09"
            output: "1e-09"
            cache_read: "1e-09"
        openai/qwen2.5-0.5b:
          cost:
            input: "1e-09"
            output: "1e-09"
            cache_read: "1e-09"

network:
  allowed:
    - defaults
    - host.docker.internal

max-ai-credits: 50
max-turns: 1

steps:
  - uses: actions/checkout@v6
    with:
      persist-credentials: false

  - name: Check gh-aw runner prerequisites
    run: bash scripts/check-gh-aw-runner.sh

  - name: Configure local model host alias
    run: |
      bridge_ip="$(docker network inspect bridge --format '{{range .IPAM.Config}}{{if .Gateway}}{{.Gateway}}{{end}}{{end}}' 2>/dev/null | sed -n '1p' || true)"
      if [ -z "$bridge_ip" ]; then
        bridge_ip="$(ip -4 addr show docker0 2>/dev/null | awk '/inet / { sub(/\/.*/, "", $2); print $2; exit }')"
      fi
      if [ -z "$bridge_ip" ]; then
        echo "Could not determine Docker bridge host address for host.docker.internal" >&2
        exit 1
      fi

      sudo sed -i.bak '/[[:space:]]host\.docker\.internal\([[:space:]]\|$\)/d' /etc/hosts
      printf '%s host.docker.internal\n' "$bridge_ip" | sudo tee -a /etc/hosts >/dev/null
      echo "Mapped host.docker.internal to Docker host gateway ${bridge_ip}"

  - name: Ask local model and stage issue
    env:
      LOCAL_OPENAI_BASE_URL: "${{ vars.LOCAL_AGENT_OPENAI_BASE_URL || 'http://host.docker.internal:11435/v1' }}"
      LOCAL_OPENAI_MODEL: "${{ vars.LOCAL_AGENT_OPENAI_MODEL || 'qwen2.5-0.5b' }}"
      LOCAL_OPENAI_API_KEY: "ollama"
      NANO_PROMPT: "${{ github.event.inputs.prompt || 'Reply with exactly: nano ok' }}"
      NANO_RUN_URL: "${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"
    run: |
      set -euo pipefail

      nano_dir="${RUNNER_TEMP}/gh-aw/nano"
      safe_outputs_dir="${RUNNER_TEMP}/gh-aw/safeoutputs"
      request_file="${nano_dir}/request.json"
      response_file="${nano_dir}/response.json"
      safe_outputs_file="${safe_outputs_dir}/outputs.jsonl"

      mkdir -p "$nano_dir" "$safe_outputs_dir"

      jq -n \
        --arg model "$LOCAL_OPENAI_MODEL" \
        --arg prompt "$NANO_PROMPT" \
        '{
          model: $model,
          stream: false,
          temperature: 0,
          messages: [
            {
              role: "system",
              content: "Return only the direct answer as plain text. Do not use markdown, JSON, or tool calls."
            },
            {
              role: "user",
              content: $prompt
            }
          ]
        }' > "$request_file"

      curl -fsS \
        -H "Authorization: Bearer ${LOCAL_OPENAI_API_KEY}" \
        -H "Content-Type: application/json" \
        --data @"$request_file" \
        "${LOCAL_OPENAI_BASE_URL%/}/chat/completions" > "$response_file"

      answer="$(jq -r '.choices[0].message.content // empty' "$response_file" | sed -e 's/[[:space:]]\+$//')"
      if [ -z "$answer" ]; then
        echo "Local model returned an empty answer" >&2
        jq . "$response_file" >&2
        exit 1
      fi

      body="$(
        jq -n \
          --arg prompt "$NANO_PROMPT" \
          --arg answer "$answer" \
          --arg run_url "$NANO_RUN_URL" \
          -r '"Prompt:\n\n```\n" + $prompt + "\n```\n\nModel response:\n\n```\n" + $answer + "\n```\n\nRun: " + $run_url'
      )"

      jq -cn \
        --arg title "Local model response" \
        --arg body "$body" \
        '{
          type: "create_issue",
          title: $title,
          body: $body,
          integrity: "high",
          secrecy: "public"
        }' >> "$safe_outputs_file"

      {
        echo "### Nano local model response"
        echo
        echo '```'
        printf '%s\n' "$answer"
        echo '```'
      } >> "$GITHUB_STEP_SUMMARY"

---

# Nano Local Qwen Agent

The nano model-response issue has already been staged by the workflow step named `Ask local model and stage issue`.

Do not inspect files, modify files, or call tools. Finish immediately.
