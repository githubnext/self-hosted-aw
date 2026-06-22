# Agentic Workflows with self-hosted runners and local inference

This repository demonstrates how [GitHub Agentic Workflows](https://github.github.com/gh-aw/) can be used with: 

- self-hosted runners
- model-routing platforms
- local inference

You can even run your Actions jobs, including AI models, directly on your laptop or Mac Mini.

We demonstrate the following example scenarios:

- [Azure VM self-hosted runner calling OpenRouter for inference](infra/azure-vm/README.md)
- [Local Mac self-hosted runner truly local inference via Qwen running with Ollama](infra/local-macrunner-qwenollama/README.md)

Of course, you mix and match any Actions runner with any inference host, as long as they can communicate with each other.

## Why self-host?

Self-hosting runners gives you extra control over your Actions execution environment, and your choice of hosting platform. Choosing a model-routing platform like Open Router can give you access to additional models, and hosting your inference yourself can help control costs. Frontier models still require datacenter-scale resources to host, but there are models small enough to run on a MacBook Air that can still perform useful work. 

## Prerequisites

Install the GitHub CLI and the Agentic Workflows extension:

```bash
gh auth login
gh extension install github/gh-aw
```

Compile the Markdown workflow sources into GitHub Actions lock files:

```bash
gh aw compile --validate --actionlint
scripts/patch-local-qwen-awf-pricing.sh
```

The generated `.lock.yml` files are committed because GitHub Actions runs those files, not the Markdown workflow sources.

## Scenario 1: Azure VM Runner, OpenRouter Inference

Use this lane when you want the agent job to run on a Linux VM you operate, while model calls go through OpenRouter. We demonstrate using Azure, but you can easily choose any suitable VM host.

Read the full guide:

```bash
open infra/azure-vm/README.md
```

Short version:

```bash
gh aw secrets set OPENROUTER_API_KEY --value "$OPENROUTER_API_KEY"
infra/azure-vm/create-runner-vm.sh
gh workflow run azure-runner-capability-smoke.yml
gh aw run azure-vm-openrouter
```




## Scenario 2: Local Mac Runner, Local Qwen/Ollama Inference

True local inference! We use Qwen 2.5 0.5B here for demonstration purposes, which is capable of some simple tasks. We also had success using Qwen 3.6 27B, a very capable model, on a MacBook Air (though it makes the MacBook nearly unusable for other work while running). Some models that are quite close to frontier performance can be run on memory-maxed Mac Studios.

Full guide:

```bash
open infra/local-macrunner-qwenollama/README.md
```

Quick test:

```bash
scripts/run-local-macrunner-qwenollama.sh "Check the local agent lane."
```

The launcher starts or verifies Ollama on macOS, creates Qwen model aliases, boots an x86_64 Lima Linux VM, registers that VM as the GitHub Actions self-hosted runner, dispatches the workflow, and watches it.

## Runner Requirements

`gh-aw` self-hosted runners must be Linux hosts with:

- Docker.
- Passwordless sudo for the runner service account.
- iptables support.
- Outbound HTTPS access to GitHub, GHCR, and the selected engine endpoint.
- Access to any domains listed in the workflow network allowlist.

A macOS host cannot directly satisfy the Linux runner requirements for the `gh-aw` agent job, which is why the all-local Mac scenario uses Lima to run a local Linux VM. The Mac still owns the local model endpoint.

## Adapting The Pattern

Use the included scenarios as starting points:

- Change the runner labels to point at another host class.
- Change the bootstrap scripts to install your internal dependencies.
- Change `OPENAI_BASE_URL` and the engine config to point at another OpenAI-compatible gateway.
- Change the model IDs and smoke tests to match your local inference service.
- Add private network routes, mounted caches, GPUs, or internal tools to the self-hosted runner.

