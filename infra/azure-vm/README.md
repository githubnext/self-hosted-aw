# Azure VM runner lane

This lane provisions an Ubuntu VM that can host a GitHub Actions self-hosted runner for `gh-aw`.

The important labels are:

```text
self-hosted,linux,x64,azure,gh-aw
```

## Create A Runner VM

Runner settings live in `infra/azure-vm/runner.conf`:

```sh
: "${AZURE_RESOURCE_GROUP:=gh-aw-demo-runners}"
: "${AZURE_LOCATION:=eastus}"
: "${AZURE_VM_NAME:=gh-aw-azure-runner-01}"
: "${AZURE_VM_SIZE:=Standard_B2ms}"
```

From the repository root:

```bash
infra/azure-vm/create-runner-vm.sh
```

To use a different config file, set `AZURE_RUNNER_CONFIG`:

```bash
AZURE_RUNNER_CONFIG=infra/azure-vm/runner.local.conf infra/azure-vm/create-runner-vm.sh
```

The config file uses shell default assignments so GitHub Actions environment variables or matrix values can override the committed defaults without editing the file.

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
