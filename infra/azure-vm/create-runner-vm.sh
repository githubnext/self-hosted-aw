#!/usr/bin/env bash
set -euo pipefail

repo="${GITHUB_REPOSITORY:-}"
if [[ -z "$repo" ]]; then
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
fi

: "${AZURE_RESOURCE_GROUP:=gh-aw-demo-runners}"
: "${AZURE_LOCATION:=westus3}"
: "${AZURE_VM_NAME:=gh-aw-azure-runner-01}"
: "${AZURE_VM_SIZE:=Standard_D4s_v5}"
: "${AZURE_ADMIN_USER:=azureuser}"
: "${RUNNER_VERSION:=2.329.0}"
: "${RUNNER_NAME:=${AZURE_VM_NAME}}"

command -v az >/dev/null 2>&1 || {
  echo "Azure CLI is required: https://learn.microsoft.com/cli/azure/install-azure-cli" >&2
  exit 1
}

command -v gh >/dev/null 2>&1 || {
  echo "GitHub CLI is required: https://cli.github.com/" >&2
  exit 1
}

RUNNER_TOKEN="$(gh api -X POST "repos/${repo}/actions/runners/registration-token" --jq .token)"
export GITHUB_REPOSITORY="$repo" RUNNER_TOKEN RUNNER_VERSION RUNNER_NAME

tmp_cloud_init="$(mktemp)"
trap 'rm -f "$tmp_cloud_init"' EXIT

python3 - <<'PY' > "$tmp_cloud_init"
import os
from pathlib import Path

template = Path("infra/azure-vm/cloud-init.template.yaml").read_text()
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

az vm create \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$AZURE_VM_NAME" \
  --image Ubuntu2404 \
  --size "$AZURE_VM_SIZE" \
  --admin-username "$AZURE_ADMIN_USER" \
  --generate-ssh-keys \
  --custom-data "$tmp_cloud_init" \
  --tags purpose=gh-aw-self-hosted-runner provider=azure

echo "Created Azure runner VM: $AZURE_VM_NAME"
echo "Run: gh workflow run runner-capability-smoke.yml -f target=azure"
