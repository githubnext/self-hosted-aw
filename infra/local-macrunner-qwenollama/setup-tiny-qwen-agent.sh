#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"

say() {
  printf '%s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

: "${LOCAL_AGENT_MODEL:=qwen2.5:0.5b}"

normalized_model="$(printf '%s' "$LOCAL_AGENT_MODEL" | tr '[:upper:]' '[:lower:]')"
case "$normalized_model" in
  qwen*) ;;
  *) die "LOCAL_AGENT_MODEL must be a Qwen model ID. Got: ${LOCAL_AGENT_MODEL}" ;;
esac

case "$(uname -s)" in
  Darwin)
    export QWEN_OLLAMA_MODEL="${QWEN_OLLAMA_MODEL:-$LOCAL_AGENT_MODEL}"
    export QWEN_RUNNER_LABEL="${QWEN_RUNNER_LABEL:-qwen2-5-0-5b}"
    export REGISTER_MACOS_RUNNER="${REGISTER_MACOS_RUNNER:-0}"
    export SET_GITHUB_VARIABLES="${SET_GITHUB_VARIABLES:-0}"

    say "Setting up the Mac-hosted tiny Qwen/Ollama endpoint."
    say "Model: ${QWEN_OLLAMA_MODEL}"
    say "Register macOS runner: ${REGISTER_MACOS_RUNNER}"
    if [[ "${EXPOSE_OLLAMA_TO_NETWORK:-0}" == "1" ]]; then
      say "Ollama will be exposed on the Mac network interface for the local Lima VM or another Linux runner."
    else
      say "Ollama will stay bound to localhost. Set EXPOSE_OLLAMA_TO_NETWORK=1 if a Linux runner must reach this Mac over the network."
    fi
    say

    exec "${repo_root}/infra/macos/setup-local-qwen-ollama.sh"
    ;;
  Linux)
    export LOCAL_AGENT_MODEL
    say "Setting up the Linux gh-aw runner for the tiny Qwen/Ollama agent lane."
    say "Model: ${LOCAL_AGENT_MODEL}"
    say

    exec "${script_dir}/setup-linux-runner.sh"
    ;;
  *)
    die "Unsupported OS: $(uname -s). Run this helper on macOS for the model endpoint or Linux for the gh-aw runner."
    ;;
esac
