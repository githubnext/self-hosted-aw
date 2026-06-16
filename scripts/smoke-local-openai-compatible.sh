#!/usr/bin/env bash
set -euo pipefail

base_url="${LOCAL_OPENAI_BASE_URL:-${OPENAI_BASE_URL:-http://127.0.0.1:11434/v1}}"
base_url="${base_url%/}"
model="${LOCAL_OPENAI_MODEL:-${OPENAI_MODEL:-llama3.2}}"
api_key="${LOCAL_OPENAI_API_KEY:-${OPENAI_API_KEY:-ollama}}"
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
      "content": "Say that the local model endpoint is reachable from this macOS runner."
    }
  ],
  "max_tokens": 40
}
JSON

echo "Calling local OpenAI-compatible model: $model"
echo "Base URL: $base_url"

http_code="$(
  curl -sS \
    -o "$response" \
    -w "%{http_code}" \
    -X POST "${base_url}/chat/completions" \
    -H "Authorization: Bearer ${api_key}" \
    -H "Content-Type: application/json" \
    --data @"$payload"
)"

if [[ "$http_code" != 2* ]]; then
  echo "Local model request failed with HTTP $http_code" >&2
  sed -n '1,60p' "$response" >&2
  exit 1
fi

echo "Local model request succeeded with HTTP $http_code"
sed -n '1,12p' "$response"
