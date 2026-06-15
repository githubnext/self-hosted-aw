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

if [[ -n "${AZURE_ZONE:-}" ]]; then
  echo "Using AZURE_ZONE=$AZURE_ZONE from config or environment."
  echo "Unset AZURE_ZONE to try regional VM placement before zonal placement."
fi

RUNNER_TOKEN="$(gh api -X POST "repos/${repo}/actions/runners/registration-token" --jq .token)"
export GITHUB_REPOSITORY="$repo" RUNNER_TOKEN RUNNER_VERSION RUNNER_NAME CLOUD_INIT_TEMPLATE="${script_dir}/cloud-init.template.yaml"

tmp_cloud_init="$(mktemp)"
attempt_log="$(mktemp)"
trap 'rm -f "$tmp_cloud_init" "$attempt_log"' EXIT

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

locations="$AZURE_LOCATION ${AZURE_FALLBACK_LOCATIONS:-}"
sizes="$AZURE_VM_SIZE ${AZURE_FALLBACK_VM_SIZES:-}"
zones="${AZURE_ZONE:-none} ${AZURE_FALLBACK_ZONES:-}"

attempt=0
for location in $locations; do
  for size in $sizes; do
    for zone in $zones; do
      attempt=$((attempt + 1))
      zone_label="$zone"
      if [[ "$zone" == "none" ]]; then
        zone_label="regional"
      fi

      echo "Trying Azure VM create attempt $attempt: location=$location size=$size zone=$zone_label"

      vm_create_args=(
        --resource-group "$AZURE_RESOURCE_GROUP"
        --name "$AZURE_VM_NAME"
        --location "$location"
        --image Ubuntu2404
        --size "$size"
        --admin-username "$AZURE_ADMIN_USER"
        --generate-ssh-keys
        --custom-data "$tmp_cloud_init"
        --tags purpose=gh-aw-self-hosted-runner provider=azure
      )

      if [[ "$zone" != "none" ]]; then
        vm_create_args+=(--zone "$zone")
      fi

      if az vm create "${vm_create_args[@]}" >"$attempt_log" 2>&1; then
        cat "$attempt_log"
        echo "Created Azure runner VM: $AZURE_VM_NAME"
        echo "Location: $location"
        echo "Size: $size"
        echo "Zone: $zone_label"
        echo "Run: gh workflow run runner-capability-smoke.yml -f target=azure"
        exit 0
      fi

      echo "Azure VM create attempt failed."
      grep -E "(SkuNotAvailable|AllocationFailed|InvalidTemplateDeployment|InvalidAvailabilityZone|OperationNotAllowed|Code:|Message:)" "$attempt_log" | tail -8 || tail -20 "$attempt_log"
      echo
    done
  done
done

echo "All Azure VM create attempts failed. Last Azure CLI output:" >&2
tail -80 "$attempt_log" >&2
exit 1
