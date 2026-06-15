# Azure VM runner lane

This lane provisions an Ubuntu VM that can host a GitHub Actions self-hosted runner for `gh-aw`.

The important labels are:

```text
self-hosted,linux,x64,azure,gh-aw
```

## Create A Runner VM

Runner settings live in `infra/azure-vm/runner.conf`:

```sh
: "${AZURE_SUBSCRIPTION_ID:=41035778-206b-4ce2-9ec4-07987c6a7e06}"
: "${AZURE_RESOURCE_GROUP:=gh-aw-demo-runners}"
: "${AZURE_LOCATION:=eastus}"
: "${AZURE_VM_NAME:=gh-aw-azure-runner-01}"
: "${AZURE_VM_SIZE:=Standard_B2ms}"
: "${AZURE_FALLBACK_LOCATIONS=eastus2 centralus southcentralus westus2}"
: "${AZURE_FALLBACK_VM_SIZES=Standard_D2s_v5 Standard_D2as_v5 Standard_B2s}"
: "${AZURE_FALLBACK_ZONES=}"
```

From the repository root:

```bash
infra/azure-vm/create-runner-vm.sh
```

To use a different config file, set `AZURE_RUNNER_CONFIG`:

```bash
AZURE_RUNNER_CONFIG=infra/azure-vm/runner.local.conf infra/azure-vm/create-runner-vm.sh
```

The config file uses shell default assignments so GitHub Actions environment variables or matrix values can override the committed defaults without editing the file. The helper tries the preferred `AZURE_LOCATION` and `AZURE_VM_SIZE` first, then walks the configured fallback locations, sizes, and optional zones when Azure reports SKU capacity restrictions.

The helper obtains a short-lived GitHub runner registration token with `gh api`, renders `cloud-init.template.yaml`, and creates the VM with Docker, sudo, iptables, and the runner service configured.

After the VM appears in GitHub repository settings, run:

```bash
gh workflow run runner-capability-smoke.yml -f target=azure
gh aw run azure-vm-openrouter
```

## Clean Up

```bash
. infra/azure-vm/runner.conf
az group delete --name "$AZURE_RESOURCE_GROUP"
```
