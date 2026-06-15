# Azure VM runner lane

This lane provisions an Ubuntu VM that can host a GitHub Actions self-hosted runner for `gh-aw`.

The important labels are:

```text
self-hosted,linux,x64,azure,gh-aw
```

## Create A Runner VM

From the repository root:

```bash
export AZURE_RESOURCE_GROUP=gh-aw-demo-runners
export AZURE_LOCATION=westus3
export AZURE_VM_NAME=gh-aw-azure-runner-01
export AZURE_VM_SIZE=Standard_D2s_v5
# Optional: set AZURE_ZONE=1, 2, or 3 if Azure reports regional capacity restrictions.

infra/azure-vm/create-runner-vm.sh
```

The helper obtains a short-lived GitHub runner registration token with `gh api`, renders `cloud-init.template.yaml`, and creates the VM with Docker, sudo, iptables, and the runner service configured.

After the VM appears in GitHub repository settings, run:

```bash
gh workflow run runner-capability-smoke.yml -f target=azure
gh aw run azure-vm-openrouter
```

## Clean Up

```bash
az group delete --name "$AZURE_RESOURCE_GROUP"
```
