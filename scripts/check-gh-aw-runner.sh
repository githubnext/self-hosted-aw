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

check_egress() {
  local url="$1"
  local code

  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 15 "$url" || true)"
  if [[ "$code" =~ ^[1-5][0-9][0-9]$ ]]; then
    ok "reachable: $url (HTTP $code)"
  else
    fail "not reachable: $url"
  fi
}

say "== runner identity =="
say "user: $(id -un)"
say "uid/gid: $(id -u):$(id -g)"
say "kernel: $(uname -a)"
say "workspace: ${GITHUB_WORKSPACE:-$(pwd)}"
say "runner: ${RUNNER_NAME:-unknown}"
say "runner temp: ${RUNNER_TEMP:-unset}"
say

say "== operating system =="
if [[ "$(uname -s)" == "Linux" ]]; then
  ok "Linux runner detected"
else
  fail "gh-aw self-hosted runners must be Linux"
fi

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  say "distribution: ${PRETTY_NAME:-unknown}"
fi
say

say "== required tools =="
check_command curl
check_command docker
check_command git
check_command iptables
check_command sudo
say

say "== sudo =="
if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  ok "passwordless sudo is available"
else
  fail "passwordless sudo is required for gh-aw firewall setup"
fi

if command -v iptables >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
  if sudo -n iptables -S >/dev/null 2>&1; then
    ok "iptables can be inspected with sudo"
  else
    fail "iptables is present but cannot be inspected with passwordless sudo"
  fi
fi
say

say "== docker =="
if command -v docker >/dev/null 2>&1; then
  if docker version >/dev/null 2>&1; then
    ok "Docker daemon is reachable"
    docker version --format 'client={{.Client.Version}} server={{.Server.Version}}' || true
  else
    fail "Docker daemon is not reachable by the runner user"
  fi

  if docker info >/dev/null 2>&1; then
    ok "docker info succeeded"
  else
    fail "docker info failed"
  fi
fi

if [[ -S /var/run/docker.sock ]]; then
  ok "/var/run/docker.sock exists"
else
  warn "/var/run/docker.sock was not found; DOCKER_HOST=${DOCKER_HOST:-unset}"
fi
say

say "== egress =="
for url in \
  "https://github.com" \
  "https://api.github.com" \
  "https://ghcr.io/v2/" \
  "https://openrouter.ai"; do
  check_egress "$url"
done
say

if [[ "$failed" -eq 0 ]]; then
  ok "runner satisfies the demonstrator checks"
else
  fail "runner is missing one or more required capabilities"
  exit 1
fi
