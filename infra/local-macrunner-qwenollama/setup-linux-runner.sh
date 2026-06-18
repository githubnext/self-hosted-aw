#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config_file="${LOCAL_MACRUNNER_CONFIG:-${script_dir}/runner.conf}"

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

sudo_cmd() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

run_as_runner_user() {
  sudo -u "$RUNNER_USER" "$@"
}

if [[ -f "$config_file" ]]; then
  # shellcheck source=/dev/null
  . "$config_file"
else
  die "local Mac runner config file not found: $config_file"
fi

if [[ "$(uname -s)" != "Linux" ]]; then
  die "This helper must be run on Linux. Use it inside the Linux VM or host that will run gh-aw."
fi

if [[ "$(uname -m)" != "x86_64" ]]; then
  die "This workflow currently targets x64 Linux runners. Found: $(uname -m)"
fi

repo="${GITHUB_REPOSITORY:-}"
if [[ -z "$repo" ]]; then
  have gh || die "GitHub CLI is required before repo autodetection. Install gh or set GITHUB_REPOSITORY=OWNER/REPO."
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
fi

default_host="$(hostname -s 2>/dev/null || hostname)"
default_host="$(printf '%s' "$default_host" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]-' '-')"
default_host="${default_host%-}"
if [[ -z "${RUNNER_NAME:-}" ]]; then
  RUNNER_NAME="${default_host:-linux}-local-macrunner-qwenollama"
fi

normalize_qwen_model() {
  local normalized
  local normalized_alias
  local normalized_provider_alias

  normalized="$(printf '%s' "$LOCAL_AGENT_MODEL" | tr '[:upper:]' '[:lower:]')"
  case "$normalized" in
    qwen*) ;;
    *) die "LOCAL_AGENT_MODEL must be a Qwen model ID. Got: ${LOCAL_AGENT_MODEL}" ;;
  esac

  normalized_alias="$(printf '%s' "$LOCAL_AGENT_MODEL_ALIAS" | tr '[:upper:]' '[:lower:]')"
  case "$normalized_alias" in
    qwen*) ;;
    *) die "LOCAL_AGENT_MODEL_ALIAS must be a Qwen model ID. Got: ${LOCAL_AGENT_MODEL_ALIAS}" ;;
  esac

  if [[ ! "$LOCAL_AGENT_MODEL_ALIAS" =~ ^[A-Za-z][A-Za-z0-9._-]*$ ]]; then
    die "LOCAL_AGENT_MODEL_ALIAS must be AWF-safe: letters, digits, dot, underscore, and hyphen only. Got: ${LOCAL_AGENT_MODEL_ALIAS}"
  fi

  normalized_provider_alias="$(printf '%s' "$LOCAL_AGENT_PROVIDER_MODEL_ALIAS" | tr '[:upper:]' '[:lower:]')"
  case "$normalized_provider_alias" in
    openai/qwen*) ;;
    *) die "LOCAL_AGENT_PROVIDER_MODEL_ALIAS must be an OpenAI-qualified Qwen model ID. Got: ${LOCAL_AGENT_PROVIDER_MODEL_ALIAS}" ;;
  esac
}

install_packages() {
  if [[ "$INSTALL_PACKAGES" != "1" ]]; then
    return 0
  fi

  have apt-get || die "Automatic package installation currently expects apt-get. Set INSTALL_PACKAGES=0 and install prerequisites manually on this distro."

  sudo_cmd apt-get update
  sudo_cmd apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    sudo

  sudo_cmd install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo_cmd tee /etc/apt/keyrings/docker.asc >/dev/null
    sudo_cmd chmod a+r /etc/apt/keyrings/docker.asc
  fi

  if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" |
      sudo_cmd tee /etc/apt/sources.list.d/docker.list >/dev/null
  fi

  if [[ ! -f /etc/apt/keyrings/githubcli-archive-keyring.gpg ]]; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg |
      sudo_cmd tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
    sudo_cmd chmod a+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  fi

  if [[ ! -f /etc/apt/sources.list.d/github-cli.list ]]; then
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" |
      sudo_cmd tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  fi

  sudo_cmd apt-get update
  sudo_cmd apt-get install -y \
    docker-buildx-plugin \
    docker-ce \
    docker-ce-cli \
    docker-compose-plugin \
    git \
    gh \
    iptables \
    jq \
    nodejs \
    npm \
    python3 \
    socat \
    tar

  sudo_cmd systemctl enable --now docker
}

ensure_gh_auth() {
  have gh || die "GitHub CLI is required and must be authenticated before registering the runner."
  gh auth status >/dev/null 2>&1 || die "GitHub CLI is not authenticated. Run: gh auth login"
}

agent_base_url() {
  local listen_port="${OLLAMA_PROXY_LISTEN##*:}"

  printf 'http://host.docker.internal:%s/v1\n' "$listen_port"
}

configure_repo_variables() {
  if [[ "$SET_GITHUB_VARIABLES" != "1" ]]; then
    return 0
  fi

  gh variable set LOCAL_AGENT_OPENAI_BASE_URL --repo "$repo" --body "$(agent_base_url)"
  gh variable set LOCAL_AGENT_OPENAI_MODEL --repo "$repo" --body "$LOCAL_AGENT_PROVIDER_MODEL_ALIAS"
}

ensure_runner_user() {
  if ! id "$RUNNER_USER" >/dev/null 2>&1; then
    sudo_cmd useradd --create-home --shell /bin/bash "$RUNNER_USER"
  fi

  sudo_cmd usermod -aG sudo "$RUNNER_USER"
  sudo_cmd usermod -aG docker "$RUNNER_USER"
  printf '%s ALL=(ALL) NOPASSWD:SETENV:ALL\n' "$RUNNER_USER" |
    sudo_cmd tee "/etc/sudoers.d/${RUNNER_USER}-gh-aw" >/dev/null
  sudo_cmd chmod 0440 "/etc/sudoers.d/${RUNNER_USER}-gh-aw"
}

prepare_gh_aw_home() {
  sudo_cmd install -d -o "$RUNNER_USER" -g "$RUNNER_USER" -m 0755 /home/runner /home/runner/.copilot
}

configure_runner_npm() {
  local npm_cache_dir="${RUNNER_DIR}/_work/_tool/npm-cache"
  local runner_home

  runner_home="$(getent passwd "$RUNNER_USER" | awk -F: '{print $6}')"
  [[ -n "$runner_home" ]] || die "Could not determine home directory for runner user: $RUNNER_USER"

  sudo_cmd install -d -o "$RUNNER_USER" -g "$RUNNER_USER" -m 0755 "$runner_home"
  sudo_cmd install -d -o "$RUNNER_USER" -g "$RUNNER_USER" -m 0755 "$npm_cache_dir"
  sudo_cmd chown -R "$RUNNER_USER:$RUNNER_USER" "$npm_cache_dir"
  if [[ -d "${runner_home}/.npm" ]]; then
    sudo_cmd chown -R "$RUNNER_USER:$RUNNER_USER" "${runner_home}/.npm"
  fi

  sudo_cmd tee "${runner_home}/.npmrc" >/dev/null <<EOF
audit=false
fund=false
cache=${npm_cache_dir}
EOF
  sudo_cmd chown "$RUNNER_USER:$RUNNER_USER" "${runner_home}/.npmrc"
  sudo_cmd chmod 0644 "${runner_home}/.npmrc"
}

install_npm_wrapper() {
  if [[ ! -x /usr/bin/npm ]]; then
    return 0
  fi

  sudo_cmd tee /usr/local/bin/npm >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

real_npm=/usr/bin/npm

is_gh_aw_artifact_install() {
  [[ "$PWD" == */_work/_temp/gh-aw/actions ]] || return 1
  [[ "${1:-}" == "install" ]] || return 1

  local arg
  for arg in "$@"; do
    if [[ "$arg" == "@actions/artifact@^6.0.0" ]]; then
      return 0
    fi
  done

  return 1
}

if is_gh_aw_artifact_install "$@"; then
  moved_package_json=0
  original_package_json=""

  if [[ -f package.json ]]; then
    original_package_json="$(mktemp package.json.XXXXXX)"
    mv package.json "$original_package_json"
    moved_package_json=1
  fi

  restore_package_json() {
    status=$?
    rm -f package.json
    if [[ "$moved_package_json" == "1" && -n "$original_package_json" ]]; then
      mv "$original_package_json" package.json
    fi
    exit "$status"
  }

  trap restore_package_json EXIT
  printf '{"private":true}\n' > package.json
  "$real_npm" "$@"
  exit "$?"
fi

exec "$real_npm" "$@"
EOF
  sudo_cmd chmod 0755 /usr/local/bin/npm
}

clean_gh_aw_temp() {
  if [[ -d "${RUNNER_DIR}/_work/_temp/gh-aw" ]]; then
    sudo_cmd rm -rf "${RUNNER_DIR}/_work/_temp/gh-aw"
  fi
}

parse_url_host_port() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import urlparse

url = sys.argv[1]
parsed = urlparse(url)
if parsed.scheme not in ("http", "https") or not parsed.hostname:
    raise SystemExit(f"unsupported URL: {url}")
port = parsed.port or (443 if parsed.scheme == "https" else 80)
print(parsed.hostname)
print(port)
PY
}

default_gateway_base_url() {
  local gateway

  gateway="$(ip route 2>/dev/null | awk '/^default / {print $3; exit}')"
  if [[ -n "$gateway" ]]; then
    printf 'http://%s:11434/v1\n' "$gateway"
  fi
}

candidate_upstreams() {
  if [[ -n "$OLLAMA_UPSTREAM_BASE_URL" ]]; then
    printf '%s\n' "$OLLAMA_UPSTREAM_BASE_URL"
    return 0
  fi

  printf '%s\n' \
    "http://host.docker.internal:11434/v1" \
    "http://host.lima.internal:11434/v1"
  default_gateway_base_url
}

select_upstream() {
  local candidate
  local base_url

  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    base_url="${candidate%/}"
    if curl -fsS --connect-timeout 3 --max-time 10 "${base_url}/models" >/dev/null 2>&1; then
      printf '%s\n' "$base_url"
      return 0
    fi
    warn "Ollama upstream not reachable yet: ${base_url}/models"
  done < <(candidate_upstreams)

  return 1
}

configure_host_alias() {
  if getent hosts host.docker.internal 2>/dev/null | awk '$1 == "127.0.0.1" { found = 1 } END { exit found ? 0 : 1 }'; then
    return 0
  fi

  sudo_cmd sed -i.bak '/[[:space:]]host\.docker\.internal\([[:space:]]\|$\)/d' /etc/hosts
  printf '127.0.0.1 host.docker.internal\n' | sudo_cmd tee -a /etc/hosts >/dev/null
}

configure_ollama_proxy() {
  local upstream_base_url="$1"
  local listen_host="${OLLAMA_PROXY_LISTEN%:*}"
  local listen_port="${OLLAMA_PROXY_LISTEN##*:}"
  local proxy_url="http://host.docker.internal:${listen_port}/v1/models"
  local proxy_ready=0
  local upstream_host
  local upstream_port
  local parsed
  local attempt=0

  parsed="$(parse_url_host_port "$upstream_base_url")"
  upstream_host="$(printf '%s\n' "$parsed" | sed -n '1p')"
  upstream_port="$(printf '%s\n' "$parsed" | sed -n '2p')"

  sudo_cmd tee /etc/systemd/system/gh-aw-ollama-proxy.service >/dev/null <<EOF
[Unit]
Description=Proxy local gh-aw host port ${listen_port} to Mac-hosted Ollama
After=network-online.target
Wants=network-online.target

[Service]
Restart=always
RestartSec=2
ExecStart=/usr/bin/socat TCP-LISTEN:${listen_port},bind=${listen_host},fork,reuseaddr TCP:${upstream_host}:${upstream_port}

[Install]
WantedBy=multi-user.target
EOF

  sudo_cmd systemctl daemon-reload
  sudo_cmd systemctl enable gh-aw-ollama-proxy.service
  sudo_cmd systemctl restart gh-aw-ollama-proxy.service
  configure_host_alias

  while (( attempt < 20 )); do
    attempt=$((attempt + 1))
    if curl -fsS --connect-timeout 3 --max-time 10 "$proxy_url" >/dev/null; then
      proxy_ready=1
      break
    fi
    sleep 1
  done

  if [[ "$proxy_ready" == "1" ]]; then
    say "ok: Ollama proxy is reachable at http://host.docker.internal:${listen_port}/v1"
  else
    die "Ollama proxy did not become reachable at http://host.docker.internal:${listen_port}/v1"
  fi
}

register_runner() {
  local runner_arch="x64"
  local runner_url
  local runner_token

  if [[ -x "${RUNNER_DIR}/run.sh" ]]; then
    say "Linux gh-aw runner already exists: ${RUNNER_DIR}"
    if [[ "$INSTALL_RUNNER_SERVICE" == "1" && -x "${RUNNER_DIR}/svc.sh" ]]; then
      sudo_cmd bash -lc "cd '${RUNNER_DIR}' && ./svc.sh install '${RUNNER_USER}' >/dev/null 2>&1 || true && ./svc.sh start"
    fi
    return 0
  fi

  runner_token="$(gh api -X POST "repos/${repo}/actions/runners/registration-token" --jq .token)"
  runner_url="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${runner_arch}-${RUNNER_VERSION}.tar.gz"

  sudo_cmd install -o "$RUNNER_USER" -g "$RUNNER_USER" -m 0755 -d "$RUNNER_DIR"
  run_as_runner_user bash -lc "cd '${RUNNER_DIR}' && curl -fsSL -o actions-runner.tar.gz '${runner_url}'"
  run_as_runner_user bash -lc "cd '${RUNNER_DIR}' && tar xzf actions-runner.tar.gz && rm actions-runner.tar.gz"
  run_as_runner_user bash -lc "cd '${RUNNER_DIR}' && ./config.sh --unattended --replace --url 'https://github.com/${repo}' --token '${runner_token}' --name '${RUNNER_NAME}' --labels '${RUNNER_LABELS}'"

  if [[ "$INSTALL_RUNNER_SERVICE" == "1" ]]; then
    sudo_cmd bash -lc "cd '${RUNNER_DIR}' && ./svc.sh install '${RUNNER_USER}' && ./svc.sh start"
    say "Installed and started Linux gh-aw runner service: ${RUNNER_NAME}"
  else
    say "Configured Linux gh-aw runner: ${RUNNER_NAME}"
    say "Start it with: sudo -u '${RUNNER_USER}' bash -lc 'cd ${RUNNER_DIR} && ./run.sh'"
  fi
}

normalize_qwen_model
install_packages
ensure_gh_auth
ensure_runner_user
prepare_gh_aw_home
configure_runner_npm
install_npm_wrapper
clean_gh_aw_temp

upstream="$(select_upstream || true)"
if [[ -z "$upstream" ]]; then
  die "Could not find a reachable Mac-hosted Ollama endpoint. Set OLLAMA_UPSTREAM_BASE_URL=http://MAC_HOST_OR_IP:11434/v1 and rerun."
fi

say "Using Ollama upstream: ${upstream}"
configure_ollama_proxy "$upstream"
configure_repo_variables
register_runner

say
say "Linux local Mac Qwen/Ollama runner setup complete."
say "Runner labels: self-hosted,linux,x64,${RUNNER_LABELS}"
say "Ollama source model: ${LOCAL_AGENT_MODEL}"
say "Agent workflow model alias: ${LOCAL_AGENT_MODEL_ALIAS}"
say "Codex provider model alias: ${LOCAL_AGENT_PROVIDER_MODEL_ALIAS}"
say "Agent workflow endpoint from gh-aw: $(agent_base_url)"
