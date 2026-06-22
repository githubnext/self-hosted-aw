#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

lock_file="${1:-${repo_root}/.github/workflows/local-macrunner-qwenollama.lock.yml}"
input_price="${LOCAL_QWEN_AWF_INPUT_PRICE:-0.000001}"
output_price="${LOCAL_QWEN_AWF_OUTPUT_PRICE:-0.000001}"
cached_input_price="${LOCAL_QWEN_AWF_CACHED_INPUT_PRICE:-}"
disable_ai_credits_guard="${LOCAL_QWEN_AWF_DISABLE_AI_CREDITS_GUARD:-1}"
direct_base_url="${LOCAL_QWEN_OPENAI_BASE_URL:-http://host.docker.internal:11435/v1}"
host_ports="${LOCAL_QWEN_AWF_HOST_PORTS:-80,443,8080,11435}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v node >/dev/null 2>&1 || die "node is required to patch ${lock_file}"
[[ -f "$lock_file" ]] || die "lock file not found: ${lock_file}"

LOCK_FILE="$lock_file" \
LOCAL_QWEN_AWF_INPUT_PRICE="$input_price" \
LOCAL_QWEN_AWF_OUTPUT_PRICE="$output_price" \
LOCAL_QWEN_AWF_CACHED_INPUT_PRICE="$cached_input_price" \
LOCAL_QWEN_AWF_DISABLE_AI_CREDITS_GUARD="$disable_ai_credits_guard" \
LOCAL_QWEN_OPENAI_BASE_URL="$direct_base_url" \
LOCAL_QWEN_AWF_HOST_PORTS="$host_ports" \
node <<'NODE'
const fs = require("fs");

const lockFile = process.env.LOCK_FILE;
const input = Number(process.env.LOCAL_QWEN_AWF_INPUT_PRICE);
const output = Number(process.env.LOCAL_QWEN_AWF_OUTPUT_PRICE);
const cachedInputRaw = process.env.LOCAL_QWEN_AWF_CACHED_INPUT_PRICE || "";
const disableAiCreditsGuardRaw = process.env.LOCAL_QWEN_AWF_DISABLE_AI_CREDITS_GUARD || "1";
const directBaseUrl = process.env.LOCAL_QWEN_OPENAI_BASE_URL || "http://host.docker.internal:11435/v1";
const hostPorts = process.env.LOCAL_QWEN_AWF_HOST_PORTS || "80,443,8080,11435";

function shellQuote(value) {
  return `'${value.replace(/'/g, `'\\''`)}'`;
}

if (!Number.isFinite(input) || input < 0) {
  throw new Error(`LOCAL_QWEN_AWF_INPUT_PRICE must be a non-negative number: ${process.env.LOCAL_QWEN_AWF_INPUT_PRICE}`);
}

if (!Number.isFinite(output) || output < 0) {
  throw new Error(`LOCAL_QWEN_AWF_OUTPUT_PRICE must be a non-negative number: ${process.env.LOCAL_QWEN_AWF_OUTPUT_PRICE}`);
}

if (!["0", "1"].includes(disableAiCreditsGuardRaw)) {
  throw new Error(`LOCAL_QWEN_AWF_DISABLE_AI_CREDITS_GUARD must be 0 or 1: ${disableAiCreditsGuardRaw}`);
}

const disableAiCreditsGuard = disableAiCreditsGuardRaw === "1";
const parsedDirectBaseUrl = new URL(directBaseUrl);
if (!["http:", "https:"].includes(parsedDirectBaseUrl.protocol)) {
  throw new Error(`LOCAL_QWEN_OPENAI_BASE_URL must be http or https: ${directBaseUrl}`);
}

if (!/^[0-9]+(,[0-9]+)*$/.test(hostPorts)) {
  throw new Error(`LOCAL_QWEN_AWF_HOST_PORTS must be a comma-separated list of ports: ${hostPorts}`);
}

const directPort = parsedDirectBaseUrl.port || (parsedDirectBaseUrl.protocol === "https:" ? "443" : "80");
if (!hostPorts.split(",").includes(directPort)) {
  throw new Error(`LOCAL_QWEN_AWF_HOST_PORTS must include the local model port ${directPort}: ${hostPorts}`);
}

let cachedInput;
if (cachedInputRaw !== "") {
  cachedInput = Number(cachedInputRaw);
  if (!Number.isFinite(cachedInput) || cachedInput < 0) {
    throw new Error(`LOCAL_QWEN_AWF_CACHED_INPUT_PRICE must be a non-negative number: ${cachedInputRaw}`);
  }
}

const original = fs.readFileSync(lockFile, "utf8");
const awfConfigPattern = /printf '%s\\n' '({"\$schema":"https:\/\/github\.com\/github\/gh-aw-firewall\/releases\/download\/[^']+\/awf-config\.schema\.json"[^']*})' > "\$\{RUNNER_TEMP\}\/gh-aw\/awf-config\.json"/g;
let patchedCount = 0;

let patched = original.replace(awfConfigPattern, (fullMatch, rawJson) => {
  const config = JSON.parse(rawJson);
  config.apiProxy ||= {};
  config.apiProxy.enabled = false;
  config.apiProxy.enableTokenSteering = false;
  config.apiProxy.defaultAiCreditsPricing = { input, output };
  if (cachedInput !== undefined) {
    config.apiProxy.defaultAiCreditsPricing.cachedInput = cachedInput;
  }
  if (disableAiCreditsGuard) {
    delete config.apiProxy.maxAiCredits;
  }

  patchedCount += 1;
  return fullMatch.replace(rawJson, JSON.stringify(config));
});

if (patchedCount !== 1) {
  throw new Error(`expected to patch exactly one AWF config JSON block in ${lockFile}, patched ${patchedCount}`);
}

let codexProviderCount = 0;
patched = patched.replace(
  /(^[ \t]*model_provider = )"openai-proxy"(\n\n[ \t]*)\[model_providers\.openai-proxy\]\n([ \t]*)name = "OpenAI AWF proxy"\n\3base_url = "http:\/\/172\.30\.0\.30:10000"/m,
  (_match, providerPrefix, providerIndent, propertyIndent) => {
    codexProviderCount += 1;
    const tomlBaseUrl = directBaseUrl.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
    return `${providerPrefix}"local-qwen-ollama"${providerIndent}[model_providers.local-qwen-ollama]\n${propertyIndent}name = "Local Qwen/Ollama"\n${propertyIndent}base_url = "${tomlBaseUrl}"`;
  }
);

const awkReplacements = [
  ["BEGIN { skip_openai_proxy = 0 }", "BEGIN { skip_local_qwen_ollama = 0 }"],
  [
    "/^\\[model_providers\\.openai-proxy\\][[:space:]]*$/ { skip_openai_proxy = 1; next }",
    "/^\\[model_providers\\.local-qwen-ollama\\][[:space:]]*$/ { skip_local_qwen_ollama = 1; next }",
  ],
  ["/^\\[/ { skip_openai_proxy = 0 }", "/^\\[/ { skip_local_qwen_ollama = 0 }"],
  ["!skip_openai_proxy { print }", "!skip_local_qwen_ollama { print }"],
];

if (codexProviderCount > 0 || patched.includes('model_provider = "local-qwen-ollama"')) {
  for (const [from, to] of awkReplacements) {
    if (patched.includes(from)) {
      patched = patched.replace(from, to);
    } else if (!patched.includes(to)) {
      throw new Error(`expected to patch generated Codex config awk rule: ${from}`);
    }
  }
}

let hostPortsCount = 0;
patched = patched.replace(/--allow-host-ports [0-9,]+/g, () => {
  hostPortsCount += 1;
  return `--allow-host-ports ${hostPorts}`;
});

if (hostPortsCount !== 1 && !patched.includes(`--allow-host-ports ${hostPorts}`)) {
  throw new Error(`expected to patch the AWF host port allowlist in ${lockFile}`);
}

const openAiExclude = " --exclude-env OPENAI_API_KEY";
patched = patched.replace(/ --env OPENAI_API_KEY=ollama/g, "");

if (!patched.includes(`--env OPENAI_BASE_URL=${shellQuote(directBaseUrl)}`)) {
  const envAllNeedle = " --env-all ";
  if (!patched.includes(envAllNeedle)) {
    throw new Error(`expected to find --env-all in AWF invocation in ${lockFile}`);
  }

  patched = patched.replace(
    envAllNeedle,
    ` --env OPENAI_BASE_URL=${shellQuote(directBaseUrl)} --env-all `
  );
}

if (!patched.includes(openAiExclude)) {
  const envAllNeedle = " --env-all ";
  if (!patched.includes(envAllNeedle)) {
    throw new Error(`expected to find --env-all in AWF invocation in ${lockFile}`);
  }

  patched = patched.replace(envAllNeedle, `${openAiExclude} --env-all `);
}

patched = patched.replace(
  /OPENAI_API_KEY: \$\{\{ secrets\.(?:CODEX_API_KEY \|\| secrets\.)?OPENAI_API_KEY \}\}/g,
  "OPENAI_API_KEY: ollama"
);
patched = patched.replace(
  /OPENAI_BASE_URL: http:\/\/host\.docker\.internal:10001/g,
  `OPENAI_BASE_URL: ${directBaseUrl}`
);

if (patched !== original) {
  fs.writeFileSync(lockFile, patched);
}

const guardStatus = disableAiCreditsGuard ? "removed apiProxy.maxAiCredits" : "kept apiProxy.maxAiCredits";
console.log(`patched ${lockFile} for direct local Qwen/Ollama routing, ${guardStatus}, and disabled apiProxy`);
NODE
