# macOS local model runner lane

This lane registers a local macOS self-hosted GitHub Actions runner and smoke-tests an OpenAI-compatible local model endpoint.

The workflow targets these labels:

```text
self-hosted,macOS,macos-local,local-model
```

The runner can be your Mac directly, or a dedicated macOS machine. For less blast radius, prefer a dedicated user account or disposable workstation profile.

## Local Model Endpoint

The default endpoint is Ollama's OpenAI-compatible API:

```text
http://127.0.0.1:11434/v1
```

Install Ollama, start it, and pull a model:

```bash
ollama pull llama3.2
```

The workflow can be pointed at another OpenAI-compatible local server by setting repository variables:

```bash
gh variable set LOCAL_OPENAI_BASE_URL --body "http://127.0.0.1:11434/v1"
gh variable set LOCAL_OPENAI_MODEL --body "llama3.2"
```

If your local server requires an API key, set:

```bash
gh secret set LOCAL_OPENAI_API_KEY
```

Ollama ignores the API key value for its OpenAI-compatible endpoint, so no secret is needed for the default setup.

## Register The Runner

From the repository root on the Mac:

```bash
infra/macos/register-runner.sh
```

Then start the runner:

```bash
cd "$HOME/actions-runner-macos-local-model-01"
./run.sh
```

To install it as a background service instead:

```bash
INSTALL_RUNNER_SERVICE=1 infra/macos/register-runner.sh
```

## Run The Smoke Test

```bash
gh workflow run macos-local-model-smoke.yml
```
