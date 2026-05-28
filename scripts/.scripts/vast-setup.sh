#!/usr/bin/env bash
#
# Connect the current Vast instance to the local codex-gpu workflow.
#
# Sequence:
# 1. Find the running SSH-capable Vast instance, prompting if needed.
# 2. Ensure ~/.ssh/codex-key is loaded in ssh-agent.
# 3. Rewrite the managed Host codex-gpu block in ~/.ssh/config.
# 4. Wait until SSH works through codex-gpu.
# 5. Install local Ghostty terminfo on the remote host.
# 6. Upload the current dotfiles checkout and trustworthy-gradients deploy key.
# 7. Run gpu-setup.sh on the remote host.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
GPU_SETUP="$SCRIPT_DIR/gpu-setup.sh"
HOST_ALIAS="codex-gpu"
SSH_KEY="$HOME/.ssh/codex-key"
DEPLOY_KEY="$HOME/.ssh/trustworthy-gradients"
REMOTE_DEPLOY_KEY="/tmp/trustworthy-gradients.deploy-key"
REMOTE_DOTFILES_ARCHIVE="/tmp/dotfiles.tar.gz"
REMOTE_GPU_SETUP="/tmp/gpu-setup.sh"

log() {
  printf '[vast-setup] %s\n' "$*" >&2
}

die() {
  printf '[vast-setup] error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
  done
}

check_prereqs() {
  require_command vastai jq ssh scp ssh-add ssh-keygen tar

  [ -x "$GPU_SETUP" ] || die "missing executable GPU setup script: $GPU_SETUP"
  [ -d "$DOTFILES_DIR/.git" ] || die "dotfiles repo not found at $DOTFILES_DIR"
  [ -r "$SSH_KEY" ] || die "missing SSH key: $SSH_KEY"
  [ -r "$SSH_KEY.pub" ] || die "missing SSH public key: $SSH_KEY.pub"
  [ -r "$DEPLOY_KEY" ] || die "missing trustworthy-gradients deploy key: $DEPLOY_KEY"
}

ensure_codex_key_loaded() {
  local fp
  fp="$(ssh-keygen -lf "$SSH_KEY.pub" | awk '{print $2}')"

  if ssh-add -l 2>/dev/null | grep -qF "$fp"; then
    return
  fi

  if [ -t 0 ]; then
    local answer
    printf '%s is not loaded in ssh-agent. Run ssh-add now? [Y/n] ' "$SSH_KEY" >&2
    read -r answer
    case "$answer" in
      ""|y|Y|yes|YES)
        ssh-add "$SSH_KEY"
        return
        ;;
    esac
  fi

  die "$SSH_KEY is not loaded in ssh-agent"
}

running_instances() {
  vastai show instances --raw |
    jq -c '
      if type == "array" then .[]
      elif type == "object" and has("instances") then .instances[]
      else empty
      end
      | select((.ssh_host // "") != "")
      | select(((.ssh_port // "") | tostring) != "")
      | select(((.actual_status // .cur_state // "") | ascii_downcase) == "running")
    '
}

describe_instance() {
  jq -r '[
    "id=" + ((.id // .contract_id) | tostring),
    "gpu=" + ((.gpu_name // "unknown") | tostring),
    "status=" + ((.actual_status // .cur_state // "unknown") | tostring),
    "ssh=" + ((.ssh_host // "unknown") | tostring) + ":" + ((.ssh_port // "unknown") | tostring),
    "label=" + ((.label // .machine_name // "") | tostring)
  ] | join(" ")'
}

choose_instance() {
  if [ "$#" -eq 1 ]; then
    vastai show instance "$1" --raw |
      jq -c 'if type == "array" then .[0] else . end'
    return
  elif [ "$#" -gt 1 ]; then
    die "usage: vast-setup.sh [INSTANCE_ID]"
  fi

  local instances=()
  local row
  while IFS= read -r row; do
    [ -n "$row" ] && instances+=("$row")
  done < <(running_instances)

  case "${#instances[@]}" in
    0)
      die "no running Vast instances with SSH info found"
      ;;
    1)
      printf '%s\n' "${instances[0]}"
      ;;
    *)
      log "Multiple running Vast instances found:"
      local i=1
      for row in "${instances[@]}"; do
        printf '  %d) %s\n' "$i" "$(printf '%s\n' "$row" | describe_instance)" >&2
        i=$((i + 1))
      done

      printf 'Choose instance to set up: ' >&2
      local choice
      read -r choice
      case "$choice" in
        ''|*[!0-9]*)
          die "invalid choice: $choice"
          ;;
      esac
      if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#instances[@]}" ]; then
        die "invalid choice: $choice"
      fi
      printf '%s\n' "${instances[$((choice - 1))]}"
      ;;
  esac
}

update_ssh_config() {
  local instance="$1"
  local host port tmp
  host="$(printf '%s\n' "$instance" | jq -r '.ssh_host // empty')"
  port="$(printf '%s\n' "$instance" | jq -r '.ssh_port // empty')"

  [ -n "$host" ] || die "selected instance has no ssh_host"
  [ -n "$port" ] || die "selected instance has no ssh_port"

  mkdir -p "$HOME/.ssh"
  touch "$HOME/.ssh/config"
  chmod 600 "$HOME/.ssh/config"
  tmp="$(mktemp)"

  awk -v alias="$HOST_ALIAS" '
    /^# BEGIN codex-gpu managed by vast-setup.sh$/ { skip=1; next }
    /^# END codex-gpu managed by vast-setup.sh$/ { skip=0; next }
    skip { next }
    $1 == "Host" && $2 == alias { skip_host=1; next }
    skip_host && $1 == "Host" { skip_host=0 }
    skip_host { next }
    { print }
  ' "$HOME/.ssh/config" >"$tmp"

  {
    cat "$tmp"
    printf '\n# BEGIN codex-gpu managed by vast-setup.sh\n'
    printf 'Host %s\n' "$HOST_ALIAS"
    printf '  HostName %s\n' "$host"
    printf '  User root\n'
    printf '  IdentityFile %s\n' "$SSH_KEY"
    printf '  IdentitiesOnly yes\n'
    printf '  Port %s\n' "$port"
    printf '  RequestTTY force\n'
    printf '  StrictHostKeyChecking accept-new\n'
    printf '# END codex-gpu managed by vast-setup.sh\n'
  } >"$HOME/.ssh/config"

  rm -f "$tmp"
  log "Updated $HOST_ALIAS -> $host:$port"
}

wait_for_ssh() {
  local waited=0

  while [ "$waited" -le 300 ]; do
    if ssh -T -o BatchMode=yes -o ConnectTimeout=10 "$HOST_ALIAS" true >/dev/null 2>&1; then
      return
    fi

    sleep 10
    waited=$((waited + 10))
    log "Waiting for SSH... ${waited}s"
  done

  die "SSH did not become reachable through $HOST_ALIAS"
}

run_remote_setup() {
  log "Uploading deploy key, dotfiles, and GPU setup script..."
  local stage
  stage="$(mktemp -d -t vast-setup.XXXXXX)"
  trap 'rm -rf "$stage"' RETURN

  tar -czf "$stage/$(basename "$REMOTE_DOTFILES_ARCHIVE")" -C "$(dirname "$DOTFILES_DIR")" "$(basename "$DOTFILES_DIR")"
  cp "$DEPLOY_KEY" "$stage/$(basename "$REMOTE_DEPLOY_KEY")"
  cp "$GPU_SETUP" "$stage/$(basename "$REMOTE_GPU_SETUP")"
  scp "$stage/"* "$HOST_ALIAS:/tmp/"

  log "Running remote setup..."
  ssh -T "$HOST_ALIAS" \
    "REMOTE_DEPLOY_KEY='$REMOTE_DEPLOY_KEY' DOTFILES_ARCHIVE='$REMOTE_DOTFILES_ARCHIVE' bash '$REMOTE_GPU_SETUP'"
}

install_ghostty_terminfo() {
  require_command infocmp

  if ! infocmp -x xterm-ghostty >/dev/null 2>&1; then
    die "local xterm-ghostty terminfo not found"
  fi

  log "Installing Ghostty terminfo on remote..."
  infocmp -x xterm-ghostty | ssh -T "$HOST_ALIAS" 'mkdir -p ~/.terminfo && tic -x -o ~/.terminfo /dev/stdin'
}

main() {
  check_prereqs
  ensure_codex_key_loaded

  local instance
  instance="$(choose_instance "$@")"
  log "Selected $(printf '%s\n' "$instance" | describe_instance)"

  update_ssh_config "$instance"
  wait_for_ssh
  install_ghostty_terminfo
  run_remote_setup
  log "Done."
}

main "$@"
