#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

lock_file="${1:-${repo_root}/.github/workflows/local-macrunner-qwenollama.lock.yml}"
input_price="${LOCAL_QWEN_AWF_INPUT_PRICE:-0.000001}"
output_price="${LOCAL_QWEN_AWF_OUTPUT_PRICE:-0.000001}"
cached_input_price="${LOCAL_QWEN_AWF_CACHED_INPUT_PRICE:-}"
disable_ai_credits_guard="${LOCAL_QWEN_AWF_DISABLE_AI_CREDITS_GUARD:-1}"

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
node <<'NODE'
const fs = require("fs");

const lockFile = process.env.LOCK_FILE;
const input = Number(process.env.LOCAL_QWEN_AWF_INPUT_PRICE);
const output = Number(process.env.LOCAL_QWEN_AWF_OUTPUT_PRICE);
const cachedInputRaw = process.env.LOCAL_QWEN_AWF_CACHED_INPUT_PRICE || "";
const disableAiCreditsGuardRaw = process.env.LOCAL_QWEN_AWF_DISABLE_AI_CREDITS_GUARD || "1";

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

const patched = original.replace(awfConfigPattern, (fullMatch, rawJson) => {
  const config = JSON.parse(rawJson);
  config.apiProxy ||= {};
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

if (patched !== original) {
  fs.writeFileSync(lockFile, patched);
}

const guardStatus = disableAiCreditsGuard ? "removed apiProxy.maxAiCredits" : "kept apiProxy.maxAiCredits";
console.log(`patched ${lockFile} with apiProxy.defaultAiCreditsPricing and ${guardStatus}`);
NODE
