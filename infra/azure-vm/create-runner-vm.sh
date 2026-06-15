#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config_file="${AZURE_RUNNER_CONFIG:-${script_dir}/runner.conf}"

if [[ -f "$config_file" ]]; then
  # shellcheck source=/dev/null
  . "$config_file"
else
  echo "Azure runner config file not found: $config_file" >&2
  echo "Set AZURE_RUNNER_CONFIG to another config path if needed." >&2
  exit 1
fi

repo="${GITHUB_REPOSITORY:-}"
if [[ -z "$repo" ]]; then
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
fi

for required_var in \
  AZURE_RESOURCE_GROUP \
  AZURE_LOCATION \
  AZURE_VM_NAME \
  AZURE_VM_SIZE \
  AZURE_ADMIN_USER \
  RUNNER_VERSION \
  RUNNER_NAME; do
  if [[ -z "${!required_var:-}" ]]; then
    echo "Required config value is missing: $required_var" >&2
    exit 1
  fi
done

command -v az >/dev/null 2>&1 || {
  echo "Azure CLI is required: https://learn.microsoft.com/cli/azure/install-azure-cli" >&2
  exit 1
}

command -v gh >/dev/null 2>&1 || {
  echo "GitHub CLI is required: https://cli.github.com/" >&2
  exit 1
}

if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
  az account set --subscription "$AZURE_SUBSCRIPTION_ID"
fi

RUNNER_TOKEN="$(gh api -X POST "repos/${repo}/actions/runners/registration-token" --jq .token)"
export GITHUB_REPOSITORY="$repo" RUNNER_TOKEN RUNNER_VERSION RUNNER_NAME CLOUD_INIT_TEMPLATE="${script_dir}/cloud-init.template.yaml"

tmp_cloud_init="$(mktemp)"
trap 'rm -f "$tmp_cloud_init"' EXIT

python3 - <<'PY' > "$tmp_cloud_init"
import os
from pathlib import Path

template = Path(os.environ["CLOUD_INIT_TEMPLATE"]).read_text()
for key in ("GITHUB_REPOSITORY", "RUNNER_TOKEN", "RUNNER_VERSION", "RUNNER_NAME"):
    template = template.replace("${" + key + "}", os.environ[key])
print(template)
PY

if az group show --name "$AZURE_RESOURCE_GROUP" >/dev/null 2>&1; then
  echo "Using existing Azure resource group: $AZURE_RESOURCE_GROUP"
else
  az group create \
    --name "$AZURE_RESOURCE_GROUP" \
    --location "$AZURE_LOCATION"
fi

vm_create_args=(
  --resource-group "$AZURE_RESOURCE_GROUP"
  --name "$AZURE_VM_NAME"
  --location "$AZURE_LOCATION"
  --image Ubuntu2404
  --size "$AZURE_VM_SIZE"
  --admin-username "$AZURE_ADMIN_USER"
  --generate-ssh-keys
  --custom-data "$tmp_cloud_init"
  --tags purpose=gh-aw-self-hosted-runner provider=azure
)

if [[ -n "$AZURE_ZONE" ]]; then
  vm_create_args+=(--zone "$AZURE_ZONE")
fi

az vm create "${vm_create_args[@]}"

echo "Created Azure runner VM: $AZURE_VM_NAME"
echo "Run: gh workflow run runner-capability-smoke.yml -f target=azure"
