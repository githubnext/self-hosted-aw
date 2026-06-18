#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

say() {
  printf '%s\n' "$*"
}

warn() {
  printf 'warn: %s\n' "$*" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

truthy() {
  case "${1:-}" in
    1 | true | TRUE | yes | YES | y | Y) return 0 ;;
    *) return 1 ;;
  esac
}

lower_csv() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]'
}

repo_name() {
  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    printf '%s\n' "$GITHUB_REPOSITORY"
  else
    gh repo view --json nameWithOwner --jq .nameWithOwner
  fi
}

ensure_gh() {
  have gh || die "GitHub CLI is required. Install gh and run: gh auth login"
  gh auth status >/dev/null 2>&1 || die "GitHub CLI is not authenticated. Run: gh auth login"
}

ensure_gh_aw() {
  if gh aw --help >/dev/null 2>&1; then
    return 0
  fi

  say "Installing gh-aw extension."
  gh extension install github/gh-aw
}

matching_runners() {
  local repo="$1"
  local required_csv="$2"
  local require_idle="$3"
  local required=()
  local name status busy labels label ok

  IFS=',' read -r -a required <<<"$(lower_csv "$required_csv")"

  while IFS=$'\t' read -r name status busy labels; do
    [[ -n "$name" ]] || continue
    [[ "$status" == "online" ]] || continue
    if truthy "$require_idle" && [[ "$busy" != "false" ]]; then
      continue
    fi

    ok=1
    for label in "${required[@]}"; do
      [[ -n "$label" ]] || continue
      if [[ ",${labels}," != *",${label},"* ]]; then
        ok=0
        break
      fi
    done

    if [[ "$ok" == "1" ]]; then
      printf '%s\t%s\t%s\t%s\n' "$name" "$status" "$busy" "$labels"
    fi
  done < <(
    gh api "repos/${repo}/actions/runners" --paginate --jq \
      '.runners[] | [.name, .status, (.busy | tostring), ([.labels[].name | ascii_downcase] | join(","))] | @tsv'
  )
}

wait_for_runner() {
  local repo="$1"
  local required_csv="$2"
  local timeout_seconds="$3"
  local require_idle="$4"
  local started
  local runners

  started="$(date +%s)"

  while true; do
    runners="$(matching_runners "$repo" "$required_csv" "$require_idle")"
    if [[ -n "$runners" ]]; then
      say "ok: found matching runner:"
      printf '%s\n' "$runners" | awk -F '\t' '{ printf "  %s status=%s busy=%s labels=%s\n", $1, $2, $3, $4 }'
      return 0
    fi

    if (( "$(date +%s)" - started >= timeout_seconds )); then
      return 1
    fi

    sleep 5
  done
}

setup_runner_if_requested() {
  local repo="$1"
  local mode="$2"
  local should_setup=0

  case "$mode" in
    auto)
      if [[ "$(uname -s)" == "Linux" ]]; then
        should_setup=1
      fi
      ;;
    1 | true | TRUE | yes | YES)
      should_setup=1
      ;;
    0 | false | FALSE | no | NO)
      should_setup=0
      ;;
    *)
      die "SETUP_RUNNER must be auto, 1, or 0. Got: ${mode}"
      ;;
  esac

  if [[ "$should_setup" != "1" ]]; then
    if [[ "$(uname -s)" != "Linux" ]]; then
      warn "not running Linux runner setup on $(uname -s); expecting an existing Linux gh-aw runner."
    fi
    return 0
  fi

  say "Setting up or starting the Linux local Mac Qwen/Ollama gh-aw runner."
  GITHUB_REPOSITORY="$repo" "${repo_root}/infra/local-macrunner-qwenollama/setup-tiny-qwen-agent.sh"
}

latest_run_line() {
  local repo="$1"
  local workflow_file="$2"
  local ref="$3"

  gh run list \
    --repo "$repo" \
    --workflow "$workflow_file" \
    --branch "$ref" \
    --event workflow_dispatch \
    --limit 1 \
    --json databaseId,url,status,conclusion,createdAt \
    --jq '.[] | [.databaseId, .url, .status, (.conclusion // ""), .createdAt] | @tsv' |
    sed -n '1p'
}

: "${WORKFLOW_ID:=local-macrunner-qwenollama}"
: "${WORKFLOW_FILE:=local-macrunner-qwenollama.lock.yml}"
: "${REF:=main}"
: "${PROMPT:=Confirm the local Qwen/Ollama agent lane is healthy.}"
: "${RUNNER_LABELS:=self-hosted,linux,x64,local-macrunner-qwenollama,gh-aw}"
: "${SETUP_RUNNER:=auto}"
: "${WAIT_FOR_RUNNER:=1}"
: "${REQUIRE_IDLE_RUNNER:=1}"
: "${RUNNER_WAIT_SECONDS:=180}"
: "${WATCH:=1}"
: "${DRY_RUN:=0}"
: "${ENABLE_IF_NEEDED:=1}"

if [[ "$#" -gt 0 ]]; then
  PROMPT="$*"
fi

ensure_gh
ensure_gh_aw

repo="$(repo_name)"

say "== local Mac Qwen/Ollama agent workflow =="
say "repo: ${repo}"
say "workflow: ${WORKFLOW_ID}"
say "ref: ${REF}"
say "runner labels: ${RUNNER_LABELS}"
say "prompt: ${PROMPT}"
say

setup_runner_if_requested "$repo" "$SETUP_RUNNER"

if ! truthy "$DRY_RUN" && truthy "$WAIT_FOR_RUNNER"; then
  say "Waiting for a matching GitHub Actions runner."
  if ! wait_for_runner "$repo" "$RUNNER_LABELS" "$RUNNER_WAIT_SECONDS" "$REQUIRE_IDLE_RUNNER"; then
    die "No matching online runner became available within ${RUNNER_WAIT_SECONDS}s. Set WAIT_FOR_RUNNER=0 to dispatch anyway."
  fi
fi

run_args=(
  "$WORKFLOW_ID"
  --repo "$repo"
  --ref "$REF"
  -F "prompt=${PROMPT}"
)

if truthy "$ENABLE_IF_NEEDED"; then
  run_args+=(--enable-if-needed)
fi

if truthy "$DRY_RUN"; then
  run_args+=(--dry-run)
fi

say "Dispatching workflow."
gh aw run "${run_args[@]}"

if truthy "$DRY_RUN"; then
  exit 0
fi

sleep 3
run_line="$(latest_run_line "$repo" "$WORKFLOW_FILE" "$REF")"
if [[ -z "$run_line" ]]; then
  warn "Workflow dispatched, but no recent run was found yet."
  exit 0
fi

IFS=$'\t' read -r run_id run_url run_status run_conclusion run_created_at <<<"$run_line"
say "Run: ${run_url}"
say "Status: ${run_status}${run_conclusion:+ (${run_conclusion})}"
say "Created: ${run_created_at}"

if truthy "$WATCH"; then
  say
  say "Watching run ${run_id}."
  gh run watch "$run_id" --repo "$repo"
fi
