#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config_file="${MACOS_RUNNER_CONFIG:-${script_dir}/runner.conf}"

if [[ -f "$config_file" ]]; then
  # shellcheck source=/dev/null
  . "$config_file"
else
  echo "macOS runner config file not found: $config_file" >&2
  echo "Set MACOS_RUNNER_CONFIG to another config path if needed." >&2
  exit 1
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This helper must be run on macOS." >&2
  exit 1
fi

command -v gh >/dev/null 2>&1 || {
  echo "GitHub CLI is required: https://cli.github.com/" >&2
  exit 1
}

repo="${GITHUB_REPOSITORY:-}"
if [[ -z "$repo" ]]; then
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
fi

default_host="$(
  scutil --get LocalHostName 2>/dev/null ||
    scutil --get ComputerName 2>/dev/null ||
    hostname
)"
default_host="$(printf '%s' "$default_host" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]-' '-')"
default_host="${default_host%-}"
default_host="${default_host:-macos}"

if [[ -z "${RUNNER_NAME:-}" ]]; then
  RUNNER_NAME="${default_host}-local-model"
fi

if [[ -z "${RUNNER_DIR:-}" ]]; then
  RUNNER_DIR="${HOME}/actions-runner-${RUNNER_NAME}"
fi

if [[ ! -x "${RUNNER_DIR}/config.sh" ]]; then
  echo "macOS runner directory was not found or is not configured: $RUNNER_DIR"
  exit 0
fi

RUNNER_TOKEN="$(gh api -X POST "repos/${repo}/actions/runners/remove-token" --jq .token)"

cd "$RUNNER_DIR"

if [[ -x ./svc.sh ]]; then
  ./svc.sh stop >/dev/null 2>&1 || true
  ./svc.sh uninstall >/dev/null 2>&1 || true
fi

./config.sh remove --unattended --token "$RUNNER_TOKEN"

echo "Removed macOS runner registration: $RUNNER_NAME"
echo "Runner files remain at: $RUNNER_DIR"
