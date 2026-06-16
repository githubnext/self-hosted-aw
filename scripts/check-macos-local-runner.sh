#!/usr/bin/env bash
set -euo pipefail

failed=0

say() {
  printf '%s\n' "$*"
}

ok() {
  say "ok: $*"
}

warn() {
  say "warn: $*" >&2
}

fail() {
  failed=1
  say "fail: $*" >&2
}

check_command() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    ok "$name is installed: $(command -v "$name")"
  else
    fail "$name is not installed"
  fi
}

say "== runner identity =="
say "user: $(id -un)"
say "uid/gid: $(id -u):$(id -g)"
say "kernel: $(uname -a)"
say "workspace: ${GITHUB_WORKSPACE:-$(pwd)}"
say "runner: ${RUNNER_NAME:-unknown}"
say

say "== operating system =="
if [[ "$(uname -s)" == "Darwin" ]]; then
  ok "macOS runner detected"
  sw_vers || true
else
  fail "this lane requires a macOS self-hosted runner"
fi
say

say "== required tools =="
check_command curl
check_command git
say

say "== optional local-network tools =="
if command -v tailscale >/dev/null 2>&1; then
  ok "tailscale is installed: $(command -v tailscale)"
  tailscale status --self=false >/dev/null 2>&1 && ok "tailscale status succeeded" || warn "tailscale status failed or is not logged in"
else
  warn "tailscale is not installed; this is fine unless the workflow needs tailnet access"
fi
say

say "== local model endpoint =="
base_url="${LOCAL_OPENAI_BASE_URL:-${OPENAI_BASE_URL:-http://127.0.0.1:11434/v1}}"
base_url="${base_url%/}"
if curl -fsS --connect-timeout 3 --max-time 10 "${base_url}/models" >/dev/null 2>&1; then
  ok "OpenAI-compatible models endpoint is reachable: ${base_url}/models"
else
  warn "OpenAI-compatible models endpoint is not reachable yet: ${base_url}/models"
fi
say

say "== egress =="
for url in \
  "https://github.com" \
  "https://api.github.com"; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 15 "$url" || true)"
  if [[ "$code" =~ ^[1-5][0-9][0-9]$ ]]; then
    ok "reachable: $url (HTTP $code)"
  else
    fail "not reachable: $url"
  fi
done
say

if [[ "$failed" -eq 0 ]]; then
  ok "macOS runner satisfies the local-model lane checks"
else
  fail "macOS runner is missing one or more required capabilities"
  exit 1
fi
