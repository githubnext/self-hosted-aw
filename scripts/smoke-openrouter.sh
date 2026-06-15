#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
  echo "OPENROUTER_API_KEY is required" >&2
  exit 1
fi

model="${OPENROUTER_MODEL:-openai/gpt-4o-mini}"
site_url="${OPENROUTER_SITE_URL:-https://github.com/${GITHUB_REPOSITORY:-local/selfie}}"
app_name="${OPENROUTER_APP_NAME:-gh-aw-self-hosted-demo}"
payload="$(mktemp)"
response="$(mktemp)"
trap 'rm -f "$payload" "$response"' EXIT

cat > "$payload" <<JSON
{
  "model": "$model",
  "messages": [
    {
      "role": "system",
      "content": "Reply with one short sentence."
    },
    {
      "role": "user",
      "content": "Say that OpenRouter is reachable from this runner."
    }
  ],
  "max_tokens": 40
}
JSON

echo "Calling OpenRouter model: $model"

http_code="$(
  curl -sS \
    -o "$response" \
    -w "%{http_code}" \
    -X POST "https://openrouter.ai/api/v1/chat/completions" \
    -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
    -H "Content-Type: application/json" \
    -H "HTTP-Referer: ${site_url}" \
    -H "X-Title: ${app_name}" \
    --data @"$payload"
)"

if [[ "$http_code" != 2* ]]; then
  echo "OpenRouter request failed with HTTP $http_code" >&2
  sed -n '1,40p' "$response" >&2
  exit 1
fi

echo "OpenRouter request succeeded with HTTP $http_code"
sed -n '1,12p' "$response"
