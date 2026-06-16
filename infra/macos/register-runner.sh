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

repo="${GITHUB_REPOSITORY:-}"
if [[ -z "$repo" ]]; then
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
fi

case "$(uname -m)" in
  arm64) runner_arch="arm64" ;;
  x86_64) runner_arch="x64" ;;
  *)
    echo "Unsupported macOS architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

command -v gh >/dev/null 2>&1 || {
  echo "GitHub CLI is required: https://cli.github.com/" >&2
  exit 1
}

if [[ -x "${RUNNER_DIR}/run.sh" ]]; then
  echo "macOS runner already exists: $RUNNER_DIR"
  echo "Start it with: cd \"$RUNNER_DIR\" && ./run.sh"
  exit 0
fi

RUNNER_TOKEN="$(gh api -X POST "repos/${repo}/actions/runners/registration-token" --jq .token)"
runner_url="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-osx-${runner_arch}-${RUNNER_VERSION}.tar.gz"

mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

curl -fsSL -o actions-runner.tar.gz "$runner_url"
tar xzf actions-runner.tar.gz
rm actions-runner.tar.gz

./config.sh \
  --unattended \
  --replace \
  --url "https://github.com/${repo}" \
  --token "$RUNNER_TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "$RUNNER_LABELS"

if [[ "$INSTALL_RUNNER_SERVICE" == "1" ]]; then
  ./svc.sh install
  ./svc.sh start
  echo "Installed and started macOS runner service: $RUNNER_NAME"
else
  echo "Configured macOS runner: $RUNNER_NAME"
  echo "Start it with: cd \"$RUNNER_DIR\" && ./run.sh"
fi
