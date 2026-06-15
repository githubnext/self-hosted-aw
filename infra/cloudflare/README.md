# Cloudflare runner lane

The Cloudflare lane is intentionally modeled as a capability-checked runner label:

```text
self-hosted,linux,x64,cloudflare,gh-aw
```

GitHub Actions runners initiate outbound connections to GitHub, so they do not need an inbound public port. Cloudflare Tunnel is useful for administrative access to the runner host or for reaching private services from the runner without opening the host directly to the internet.

## What Must Be True

For `gh-aw` agent jobs, the runner host must provide:

- Linux.
- Docker daemon access from the runner user.
- Passwordless sudo for the runner service account.
- iptables access for the agentic workflow firewall.
- Outbound HTTPS to `github.com`, `api.github.com`, `ghcr.io`, and `openrouter.ai`.

Run this before trying the agent workflow:

```bash
gh workflow run runner-capability-smoke.yml -f target=cloudflare
```

Then run:

```bash
gh aw run cloudflare-runner-openrouter
```

## Cloudflare Workers And Containers

Cloudflare Workers are not a self-hosted runner environment. Cloudflare Containers can run general containers, but this demonstrator does not assume they can provide the host-level Docker and sudo/iptables behavior required by `gh-aw`.

Use the smoke workflow as the deciding line: if a Cloudflare-hosted compute environment passes `scripts/check-gh-aw-runner.sh`, the agentic workflow can target it through the `cloudflare` label. If it fails, keep Cloudflare in the architecture as the network/access layer and run the GitHub Actions runner on a Linux VM, metal host, or Kubernetes node that satisfies the checklist.
