# Security Review Notes

This repository intentionally introduces agentic workflows that can call OpenRouter and run on self-hosted runners.

## Reviewed Secrets

- `OPENROUTER_API_KEY`: required by the deterministic smoke test and mapped to `OPENAI_API_KEY` for the Codex engine when using OpenRouter's OpenAI-compatible endpoint.
- `OPENAI_API_KEY` and `CODEX_API_KEY`: included by the generated `gh-aw` Codex runtime validation path. The demo workflows source the provider key from `OPENROUTER_API_KEY`.
- `GITHUB_TOKEN`, `GH_AW_GITHUB_TOKEN`, and `GH_AW_GITHUB_MCP_SERVER_TOKEN`: generated `gh-aw` runtime/tooling secrets for read-only repository access and framework operation.

## Reviewed Actions

The generated `*.lock.yml` files pin `github/gh-aw-actions/setup`, `actions/checkout`, `actions/github-script`, `actions/setup-node`, `actions/download-artifact`, and `actions/upload-artifact` to commit SHAs in `.github/aw/actions-lock.json`.

## Network

The agentic workflows allow `defaults` plus `openrouter.ai`. The runner smoke test also checks outbound HTTPS reachability to GitHub, the GitHub API, GHCR, and OpenRouter.
