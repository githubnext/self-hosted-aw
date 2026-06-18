#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"

say() {
  printf '%s\n' "$*"
}

warn() {
  printf 'warn: %s\n' "$*" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

run() {
  say "+ $*"
  "$@"
}

setup_brew_shellenv() {
  if have brew; then
    return 0
  fi

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

ensure_brew() {
  setup_brew_shellenv
  if have brew; then
    say "ok: Homebrew is installed: $(command -v brew)"
    return 0
  fi

  if [[ "${INSTALL_HOMEBREW}" != "1" ]]; then
    die "Homebrew is required to install missing macOS tools. Install it first, or rerun with INSTALL_HOMEBREW=1."
  fi

  say "Installing Homebrew. This may prompt for your macOS password."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  setup_brew_shellenv
  have brew || die "Homebrew install finished, but brew is still not on PATH."
}

ensure_brew_formula() {
  local formula="$1"

  ensure_brew
  if brew list --formula "$formula" >/dev/null 2>&1; then
    say "ok: ${formula} is installed"
  else
    run brew install "$formula"
  fi
}

ensure_command_from_brew() {
  local command_name="$1"
  local formula="$2"

  if have "$command_name"; then
    say "ok: ${command_name} is installed: $(command -v "$command_name")"
  else
    ensure_brew_formula "$formula"
  fi
}

ensure_brew_cask() {
  local cask="$1"

  ensure_brew
  if brew list --cask "$cask" >/dev/null 2>&1; then
    say "ok: ${cask} is installed"
  else
    run brew install --cask "$cask"
  fi
}

repo_name() {
  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    printf '%s\n' "$GITHUB_REPOSITORY"
  else
    gh repo view --json nameWithOwner --jq .nameWithOwner
  fi
}

default_host_name() {
  local default_host

  default_host="$(
    scutil --get LocalHostName 2>/dev/null ||
      scutil --get ComputerName 2>/dev/null ||
      hostname
  )"
  default_host="$(printf '%s' "$default_host" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]-' '-')"
  default_host="${default_host%-}"
  printf '%s\n' "${default_host:-macos}"
}

ensure_gh_auth() {
  ensure_command_from_brew gh gh
  gh auth status >/dev/null 2>&1 || die "GitHub CLI is installed but not authenticated. Run: gh auth login"
}

ollama_port_from_bind() {
  local bind="$1"
  local port="${bind##*:}"

  if [[ "$port" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$port"
  else
    printf '11434\n'
  fi
}

ollama_models_dir() {
  printf '%s\n' "${OLLAMA_MODELS:-${HOME}/.ollama/models}"
}

ollama_manifest_path() {
  local model_ref="$1"
  local ref_without_tag
  local tag
  local first_component
  local manifest_root

  if [[ "${model_ref##*/}" == *":"* ]]; then
    ref_without_tag="${model_ref%:*}"
    tag="${model_ref##*:}"
  else
    ref_without_tag="$model_ref"
    tag="latest"
  fi

  first_component="${ref_without_tag%%/*}"
  manifest_root="$(ollama_models_dir)/manifests"

  if [[ "$ref_without_tag" != */* ]]; then
    printf '%s/registry.ollama.ai/library/%s/%s\n' "$manifest_root" "$ref_without_tag" "$tag"
  elif [[ "$first_component" == *.* || "$first_component" == *:* || "$first_component" == "localhost" ]]; then
    printf '%s/%s/%s\n' "$manifest_root" "$ref_without_tag" "$tag"
  else
    printf '%s/registry.ollama.ai/%s/%s\n' "$manifest_root" "$ref_without_tag" "$tag"
  fi
}

cache_manifest_path() {
  local manifest_path="$1"
  local models_dir
  local relative_path

  models_dir="$(ollama_models_dir)"
  relative_path="${manifest_path#"${models_dir}/manifests/"}"
  printf '%s/manifests/%s\n' "$OLLAMA_MANIFEST_CACHE_DIR" "$relative_path"
}

restore_ollama_manifest_cache() {
  local manifest_path="$1"
  local cached_path

  if [[ "$CACHE_OLLAMA_MANIFEST" != "1" ]]; then
    return 0
  fi

  cached_path="$(cache_manifest_path "$manifest_path")"

  if [[ -s "$manifest_path" ]]; then
    say "ok: Ollama manifest already exists: ${manifest_path}"
  elif [[ -s "$cached_path" ]]; then
    mkdir -p "$(dirname "$manifest_path")"
    cp "$cached_path" "$manifest_path"
    say "Restored cached Ollama manifest: ${cached_path}"
  else
    say "No cached Ollama manifest found yet: ${cached_path}"
  fi
}

save_ollama_manifest_cache() {
  local manifest_path="$1"
  local cached_path

  if [[ "$CACHE_OLLAMA_MANIFEST" != "1" || ! -s "$manifest_path" ]]; then
    return 0
  fi

  cached_path="$(cache_manifest_path "$manifest_path")"
  mkdir -p "$(dirname "$cached_path")"
  cp "$manifest_path" "$cached_path"
  say "Cached Ollama manifest: ${cached_path}"
}

ollama_ready() {
  curl -fsS --connect-timeout 2 --max-time 5 "${OLLAMA_HEALTH_URL}/api/version" >/dev/null 2>&1
}

wait_for_ollama() {
  local attempt=0

  while [[ "$attempt" -lt 20 ]]; do
    attempt=$((attempt + 1))
    if ollama_ready; then
      return 0
    fi
    sleep 1
  done

  return 1
}

start_ollama() {
  if [[ "$RESTART_OLLAMA" == "1" ]] && have brew && brew list --formula ollama >/dev/null 2>&1; then
    say "Starting or restarting Ollama with Homebrew services."
    brew services restart ollama >/dev/null 2>&1 || brew services start ollama >/dev/null 2>&1 || true
    wait_for_ollama && {
      say "ok: Ollama is reachable at ${OLLAMA_HEALTH_URL}"
      return 0
    }
  fi

  if ollama_ready; then
    if [[ "$RESTART_OLLAMA" == "1" && "$OLLAMA_HOST_BIND" != "127.0.0.1:11434" ]]; then
      warn "Ollama is already running. If the bind address changed, restart Ollama so OLLAMA_HOST takes effect."
    fi
    say "ok: Ollama is already reachable at ${OLLAMA_HEALTH_URL}"
    return 0
  fi

  if have brew && brew list --formula ollama >/dev/null 2>&1; then
    say "Starting Ollama with Homebrew services."
    brew services restart ollama >/dev/null 2>&1 || brew services start ollama >/dev/null 2>&1 || true
    wait_for_ollama && {
      say "ok: Ollama is reachable at ${OLLAMA_HEALTH_URL}"
      return 0
    }
  fi

  if [[ -d /Applications/Ollama.app ]]; then
    say "Starting Ollama.app."
    open -ga Ollama >/dev/null 2>&1 || open -a Ollama >/dev/null 2>&1 || true
    wait_for_ollama && {
      say "ok: Ollama is reachable at ${OLLAMA_HEALTH_URL}"
      return 0
    }
  fi

  say "Starting Ollama with a user background process."
  mkdir -p "${HOME}/Library/Logs"
  nohup env OLLAMA_HOST="$OLLAMA_HOST_BIND" ollama serve \
    >"${HOME}/Library/Logs/gh-aw-ollama.log" 2>&1 &
  wait_for_ollama || die "Ollama did not become reachable at ${OLLAMA_HEALTH_URL}. Check ${HOME}/Library/Logs/gh-aw-ollama.log."
  say "ok: Ollama is reachable at ${OLLAMA_HEALTH_URL}"
}

model_installed() {
  ollama show "$QWEN_OLLAMA_MODEL" >/dev/null 2>&1
}

configure_ollama_host() {
  say "Configuring Ollama bind address: ${OLLAMA_HOST_BIND}"
  launchctl setenv OLLAMA_HOST "$OLLAMA_HOST_BIND" || warn "could not persist OLLAMA_HOST with launchctl"
  export OLLAMA_HOST="$OLLAMA_HOST_BIND"
}

ensure_qwen_model() {
  local normalized

  normalized="$(printf '%s' "$QWEN_OLLAMA_MODEL" | tr '[:upper:]' '[:lower:]')"
  case "$normalized" in
    qwen*) ;;
    *)
      die "QWEN_OLLAMA_MODEL must be a Qwen model ID. Got: ${QWEN_OLLAMA_MODEL}"
      ;;
  esac
}

configure_repo_variables() {
  local repo="$1"

  say "Setting GitHub repository variables for ${repo}."
  gh variable set LOCAL_OPENAI_BASE_URL --repo "$repo" --body "$LOCAL_OPENAI_BASE_URL"
  gh variable set LOCAL_OPENAI_MODEL --repo "$repo" --body "$QWEN_OLLAMA_MODEL"
  gh variable set QWEN_LOCAL_OPENAI_BASE_URL --repo "$repo" --body "$LOCAL_OPENAI_BASE_URL"
  gh variable set QWEN_LOCAL_OPENAI_MODEL --repo "$repo" --body "$QWEN_OLLAMA_MODEL"
}

register_macos_runner() {
  local labels="$RUNNER_LABELS"

  if [[ ",${labels}," != *",${QWEN_RUNNER_LABEL},"* ]]; then
    labels="${labels},${QWEN_RUNNER_LABEL}"
  fi

  export INSTALL_RUNNER_SERVICE
  export MACOS_RUNNER_CONFIG="${MACOS_RUNNER_CONFIG:-${script_dir}/runner.conf}"
  export RUNNER_LABELS="$labels"
  export RUNNER_NAME="${RUNNER_NAME:-}"
  export RUNNER_DIR="${RUNNER_DIR:-}"

  say "Registering macOS runner with labels: ${RUNNER_LABELS}"
  bash "${script_dir}/register-runner.sh"
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  die "This helper must be run on macOS."
fi

: "${QWEN_OLLAMA_MODEL:=qwen3.6:27b}"
: "${QWEN_RUNNER_LABEL:=qwen3-27b}"
: "${EXPOSE_OLLAMA_TO_NETWORK:=0}"
: "${INSTALL_HOMEBREW:=0}"
: "${INSTALL_TAILSCALE:=0}"
: "${SET_GITHUB_VARIABLES:=1}"
: "${REGISTER_MACOS_RUNNER:=1}"
: "${INSTALL_RUNNER_SERVICE:=1}"
: "${RESTART_OLLAMA:=1}"
: "${PULL_MODEL:=1}"
: "${CACHE_OLLAMA_MANIFEST:=1}"
: "${RUN_SMOKE:=1}"
: "${LOCAL_OPENAI_API_KEY:=ollama}"

if [[ -z "${OLLAMA_HOST_BIND:-}" ]]; then
  if [[ "$EXPOSE_OLLAMA_TO_NETWORK" == "1" ]]; then
    OLLAMA_HOST_BIND="0.0.0.0:11434"
  else
    OLLAMA_HOST_BIND="127.0.0.1:11434"
  fi
fi

ollama_port="$(ollama_port_from_bind "$OLLAMA_HOST_BIND")"
: "${OLLAMA_HEALTH_URL:=http://127.0.0.1:${ollama_port}}"
: "${LOCAL_OPENAI_BASE_URL:=http://127.0.0.1:${ollama_port}/v1}"
: "${OLLAMA_MANIFEST_CACHE_DIR:=${XDG_CACHE_HOME:-${HOME}/.cache}/gh-aw/ollama-manifests}"
: "${RUNNER_LABELS:=macos-local,local-model,${QWEN_RUNNER_LABEL}}"

if [[ -z "${RUNNER_NAME:-}" ]]; then
  RUNNER_NAME="$(default_host_name)-${QWEN_RUNNER_LABEL}"
fi

qwen_manifest_path="$(ollama_manifest_path "$QWEN_OLLAMA_MODEL")"

say "== macOS Qwen/Ollama setup =="
say "model: ${QWEN_OLLAMA_MODEL}"
say "local OpenAI-compatible URL: ${LOCAL_OPENAI_BASE_URL}"
say "Ollama bind: ${OLLAMA_HOST_BIND}"
say "Ollama manifest: ${qwen_manifest_path}"
say "register runner: ${REGISTER_MACOS_RUNNER}"
say "runner name: ${RUNNER_NAME}"
say

ensure_qwen_model
ensure_command_from_brew curl curl
have git || warn "git was not found. The runner registration can still work, but workflows usually expect git."

ensure_command_from_brew gh gh
ensure_command_from_brew ollama ollama

if [[ "$INSTALL_TAILSCALE" == "1" ]]; then
  ensure_brew_cask tailscale
  say "Tailscale is installed. Open it and log in if this Mac needs tailnet access."
fi

configure_ollama_host
start_ollama
restore_ollama_manifest_cache "$qwen_manifest_path"

if model_installed; then
  say "ok: Qwen model is already installed: ${QWEN_OLLAMA_MODEL}"
  save_ollama_manifest_cache "$qwen_manifest_path"
elif [[ "$PULL_MODEL" == "1" ]]; then
  say "Pulling Qwen model: ${QWEN_OLLAMA_MODEL}"
  run ollama pull "$QWEN_OLLAMA_MODEL"
  save_ollama_manifest_cache "$qwen_manifest_path"
else
  warn "Qwen model is not installed and PULL_MODEL=0, so the model pull was skipped: ${QWEN_OLLAMA_MODEL}"
  save_ollama_manifest_cache "$qwen_manifest_path"
fi

if [[ "$RUN_SMOKE" == "1" ]]; then
  say "Running local Qwen smoke test."
  LOCAL_OPENAI_BASE_URL="$LOCAL_OPENAI_BASE_URL" \
    LOCAL_OPENAI_MODEL="$QWEN_OLLAMA_MODEL" \
    LOCAL_OPENAI_API_KEY="$LOCAL_OPENAI_API_KEY" \
    bash "${repo_root}/scripts/smoke-local-openai-compatible.sh"
fi

if [[ "$SET_GITHUB_VARIABLES" == "1" || "$REGISTER_MACOS_RUNNER" == "1" ]]; then
  ensure_gh_auth
fi

if [[ "$SET_GITHUB_VARIABLES" == "1" ]]; then
  configure_repo_variables "$(repo_name)"
fi

if [[ "$REGISTER_MACOS_RUNNER" == "1" ]]; then
  register_macos_runner
fi

say
say "Mac-side setup complete."
say "Run the Qwen smoke workflow with:"
say "  gh workflow run macos-qwen-local-model-smoke.yml"
say
say "If this Mac serves a nearby Linux gh-aw runner, make sure that runner can reach:"
say "  ${LOCAL_OPENAI_BASE_URL}"
say "Use EXPOSE_OLLAMA_TO_NETWORK=1 when the endpoint must be reachable beyond localhost."
