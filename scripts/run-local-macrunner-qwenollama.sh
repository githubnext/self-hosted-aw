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

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
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

ensure_lima() {
  if have limactl; then
    :
  else
    have brew || die "Lima is required for all-local Mac runner mode. Install Homebrew, or install Lima manually."

    say "Installing Lima with Homebrew."
    brew install lima
  fi

  if [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" && "$LIMA_ARCH" == "x86_64" ]]; then
    ensure_lima_x86_guestagent
  fi
}

ensure_lima_x86_guestagent() {
  local lima_share

  lima_share="$(brew --prefix lima 2>/dev/null)/share/lima"
  if [[ -f "${lima_share}/lima-guestagent.Linux-x86_64" || -f "${lima_share}/lima-guestagent.Linux-x86_64.gz" ]]; then
    return 0
  fi

  have brew || die "Homebrew is required to install Lima x86_64 guest agent support."

  say "Installing Lima x86_64 guest agent support."
  brew install lima-additional-guestagents
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

setup_local_mac_endpoint() {
  say "Setting up the Mac-hosted Qwen/Ollama endpoint."
  LOCAL_AGENT_MODEL="$LOCAL_AGENT_MODEL" \
    LOCAL_AGENT_MODEL_ALIAS="$LOCAL_AGENT_MODEL_ALIAS" \
    LOCAL_AGENT_OPENCODE_MODEL="$LOCAL_AGENT_OPENCODE_MODEL" \
    EXPOSE_OLLAMA_TO_NETWORK="${EXPOSE_OLLAMA_TO_NETWORK:-1}" \
    REGISTER_MACOS_RUNNER=0 \
    SET_GITHUB_VARIABLES=0 \
    "${repo_root}/infra/local-macrunner-qwenollama/setup-tiny-qwen-agent.sh"
}

start_lima_runner_vm() {
  local instance="$1"
  local status

  ensure_lima

  if limactl list -q | grep -Fx -- "$instance" >/dev/null 2>&1; then
    status="$(limactl list "$instance" --format '{{.Status}}')"
    if [[ "$status" == "Running" ]]; then
      say "ok: Lima runner VM is already running: ${instance}"
      return 0
    fi

    say "Starting existing Lima runner VM: ${instance}"
    limactl start --yes "$instance" >/dev/null
    return 0
  fi

  say "Creating local x86_64 Lima runner VM: ${instance}"
  say "This can take a few minutes the first time."
  limactl start --yes \
    --name="$instance" \
    --arch="$LIMA_ARCH" \
    --vm-type="$LIMA_VM_TYPE" \
    --cpus="$LIMA_CPUS" \
    --memory="$LIMA_MEMORY" \
    --disk="$LIMA_DISK" \
    "$LIMA_TEMPLATE"
}

sync_repo_to_lima() {
  local guest_repo="$1"
  local guest_repo_quoted

  guest_repo_quoted="$(shell_quote "$guest_repo")"
  say "Syncing repository snapshot into Lima VM: ${guest_repo}"

  COPYFILE_DISABLE=1 tar \
    --exclude './.git' \
    --exclude './self-hosted-aw' \
    -C "$repo_root" \
    -cf - . |
    limactl shell "$LIMA_INSTANCE" -- bash -lc "rm -rf ${guest_repo_quoted} && mkdir -p ${guest_repo_quoted} && tar -xf - -C ${guest_repo_quoted}"
}

setup_local_lima_runner() {
  local repo="$1"
  local token
  local guest_repo
  local guest_repo_quoted
  local upstream_base_url
  local guest_arch

  token="$(gh auth token)"
  [[ -n "$token" ]] || die "Could not read a GitHub token from gh auth."

  setup_local_mac_endpoint
  start_lima_runner_vm "$LIMA_INSTANCE"

  guest_arch="$(limactl shell "$LIMA_INSTANCE" -- uname -m)"
  if [[ "$guest_arch" != "x86_64" ]]; then
    die "Lima runner VM must be x86_64 for this workflow. ${LIMA_INSTANCE} is ${guest_arch}."
  fi

  guest_repo="$LIMA_GUEST_REPO_DIR"
  sync_repo_to_lima "$guest_repo"
  guest_repo_quoted="$(shell_quote "$guest_repo")"
  upstream_base_url="${OLLAMA_UPSTREAM_BASE_URL:-http://host.lima.internal:11434/v1}"

  say "Registering local Lima VM as the Linux gh-aw runner."
  say "Ollama upstream from VM: ${upstream_base_url}"
  limactl shell "$LIMA_INSTANCE" -- env \
    GITHUB_REPOSITORY="$repo" \
    GH_TOKEN="$token" \
    GITHUB_TOKEN="$token" \
    OLLAMA_UPSTREAM_BASE_URL="$upstream_base_url" \
    LOCAL_AGENT_MODEL="$LOCAL_AGENT_MODEL" \
    LOCAL_AGENT_MODEL_ALIAS="$LOCAL_AGENT_MODEL_ALIAS" \
    LOCAL_AGENT_OPENCODE_MODEL="$LOCAL_AGENT_OPENCODE_MODEL" \
    bash -lc "cd ${guest_repo_quoted} && infra/local-macrunner-qwenollama/setup-tiny-qwen-agent.sh"
}

setup_runner_if_requested() {
  local repo="$1"
  local mode="$2"
  local should_setup=0

  case "$mode" in
    auto)
      if [[ "$(uname -s)" == "Linux" || "$(uname -s)" == "Darwin" ]]; then
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

  case "$(uname -s)" in
    Darwin)
      setup_local_lima_runner "$repo"
      ;;
    Linux)
      say "Setting up or starting the Linux local Mac Qwen/Ollama gh-aw runner."
      GITHUB_REPOSITORY="$repo" "${repo_root}/infra/local-macrunner-qwenollama/setup-tiny-qwen-agent.sh"
      ;;
    *)
      die "Automatic runner setup is supported on macOS and Linux. Set SETUP_RUNNER=0 to dispatch only."
      ;;
  esac
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
: "${LOCAL_AGENT_MODEL:=qwen2.5:0.5b}"
: "${LOCAL_AGENT_MODEL_ALIAS:=qwen2.5-0.5b}"
: "${LOCAL_AGENT_OPENCODE_MODEL:=openai/${LOCAL_AGENT_MODEL_ALIAS}}"
: "${LIMA_INSTANCE:=gh-aw-local-qwen}"
: "${LIMA_TEMPLATE:=template:ubuntu-lts}"
: "${LIMA_ARCH:=x86_64}"
: "${LIMA_VM_TYPE:=qemu}"
: "${LIMA_CPUS:=2}"
: "${LIMA_MEMORY:=4}"
: "${LIMA_DISK:=30}"
: "${LIMA_GUEST_REPO_DIR:=/tmp/gh-aw-self-hosted-aw}"

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
say "Ollama source model: ${LOCAL_AGENT_MODEL}"
say "workflow model alias: ${LOCAL_AGENT_MODEL_ALIAS}"
say "OpenCode model: ${LOCAL_AGENT_OPENCODE_MODEL}"
say "prompt: ${PROMPT}"
say

if truthy "$DRY_RUN"; then
  say "Dry run: skipping local runner setup and runner wait."
elif ! truthy "$DRY_RUN"; then
  setup_runner_if_requested "$repo" "$SETUP_RUNNER"
fi

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
