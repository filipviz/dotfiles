#!/usr/bin/env bash
#
# Connect a running GPU host to the local codex-gpu workflow.
#
# Sequence:
# 1. Select a running Vast instance, RunPod pod, or Prime pod, prompting if needed.
# 2. Ensure ~/.ssh/codex-key is loaded in ssh-agent.
# 3. Rewrite the managed Host codex-gpu block in ~/.ssh/config.
# 4. Wait until SSH works through codex-gpu.
# 5. Install local Ghostty terminfo on the remote host.
# 6. Upload the current dotfiles checkout, project deploy key, and gpu-setup.sh.
# 7. Run gpu-setup.sh on the remote host.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
GPU_SETUP="$SCRIPT_DIR/gpu-setup.sh"
HOST_ALIAS="codex-gpu"
SSH_KEY="$HOME/.ssh/codex-key"
REMOTE_DOTFILES_ARCHIVE="/tmp/dotfiles.tar.gz"
REMOTE_GPU_SETUP="/tmp/gpu-setup.sh"
DEPLOY_KEY="$HOME/.ssh/trustworthy-gradients"
REMOTE_DEPLOY_KEY="/tmp/trustworthy-gradients.deploy-key"

log() {
  printf '[gpu-provision] %s\n' "$*" >&2
}

die() {
  printf '[gpu-provision] error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
  done
}

check_common_prereqs() {
  require_command jq ssh scp ssh-add ssh-keygen tar

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

vast_instance_rows() {
  vastai show instances-v1 --raw --all --status running |
    jq -c '
      def rows:
        if type == "array" then .[]
        elif type == "object" and has("instances") then .instances[]
        else empty
        end;
      rows
    '
}

vast_candidate_from_instance() {
  local instance="$1"
  local id gpu status label url endpoint hostport host port

  id="$(printf '%s\n' "$instance" | jq -r '(.id // .contract_id // "") | tostring')"
  [ -n "$id" ] || return 0

  if url="$(vastai ssh-url "$id" 2>/dev/null)"; then
    url="$(printf '%s\n' "$url" | awk 'NF { print; exit }')"
    if [[ "$url" == ssh://* ]]; then
      endpoint="${url#ssh://}"
      endpoint="${endpoint%%/*}"
      hostport="${endpoint#*@}"
      host="${hostport%:*}"
      port="${hostport##*:}"
    fi
  fi

  if [ -z "${host:-}" ] || [ -z "${port:-}" ] || [ "$host" = "$port" ]; then
    host="$(printf '%s\n' "$instance" | jq -r '
      def public_ssh_host:
        (.public_ipaddr // "") | tostring;
      def public_ssh_port:
        (.ports["22/tcp"] // [])
        | map(select((.HostPort // "") != "") | (.HostPort | tostring))
        | first // "";
      if public_ssh_host != "" and public_ssh_port != "" then public_ssh_host
      else (.ssh_host // "") | tostring
      end
    ')"
    port="$(printf '%s\n' "$instance" | jq -r '
      def public_ssh_host:
        (.public_ipaddr // "") | tostring;
      def public_ssh_port:
        (.ports["22/tcp"] // [])
        | map(select((.HostPort // "") != "") | (.HostPort | tostring))
        | first // "";
      if public_ssh_host != "" and public_ssh_port != "" then public_ssh_port
      else (.ssh_port // "") | tostring
      end
    ')"
  fi

  [ -n "$host" ] || return 0
  [ -n "$port" ] || return 0
  [ "$host" != "$port" ] || return 0

  gpu="$(printf '%s\n' "$instance" | jq -r '(.gpu_name // "unknown") | tostring')"
  status="$(printf '%s\n' "$instance" | jq -r '(.actual_status // .cur_state // "unknown") | tostring')"
  label="$(printf '%s\n' "$instance" | jq -r '(.label // .machine_name // "") | tostring')"

  jq -n -c \
    --arg provider "vast" \
    --arg id "$id" \
    --arg gpu "$gpu" \
    --arg status "$status" \
    --arg user "root" \
    --arg host "$host" \
    --arg port "$port" \
    --arg label "$label" \
    '{provider: $provider, id: $id, gpu: $gpu, status: $status, user: $user, host: $host, port: $port, label: $label}'
}

vast_candidates() {
  vast_instance_rows | while IFS= read -r instance; do
    [ -n "$instance" ] && vast_candidate_from_instance "$instance"
  done
}

runpod_pod_rows() {
  runpodctl pod list --status RUNNING --compute-type GPU -o json |
    jq -c '
      if type == "array" then .[]
      elif type == "object" and has("pods") then .pods[]
      else empty
      end
    '
}

runpod_ssh_host() {
  jq -r '
    def cmd:
      .command // .sshCommand // .ssh_command //
      (if (.ssh? | type) == "string" then .ssh else empty end) // "";

    .host // .hostname // .ip // .sshHost // .ssh_host //
    .ssh.host? // .ssh.hostname? // .connection.host? //
    (cmd | capture("@(?<host>[^[:space:]]+)")? | .host) //
    empty
  '
}

runpod_ssh_port() {
  jq -r '
    def cmd:
      .command // .sshCommand // .ssh_command //
      (if (.ssh? | type) == "string" then .ssh else empty end) // "";

    .port // .publicPort // .public_port // .sshPort // .ssh_port //
    .ssh.port? // .connection.port? //
    (cmd | capture("[[:space:]]-p[[:space:]]+(?<port>[0-9]+)")? | .port) //
    empty
    | tostring
  '
}

runpod_candidate_from_pod() {
  local pod="$1"
  local id name status gpu ssh_info host port

  id="$(printf '%s\n' "$pod" | jq -r '.id // .podId // .pod_id // .pod.id // .pod.podId // empty')"
  [ -n "$id" ] || return 0

  name="$(printf '%s\n' "$pod" | jq -r '.name // .pod.name // ""')"
  status="$(printf '%s\n' "$pod" | jq -r '.desiredStatus // .status // .runtime.status // .pod.desiredStatus // .pod.status // "unknown"')"
  gpu="$(printf '%s\n' "$pod" | jq -r '.machine.gpuDisplayName // .gpuDisplayName // .gpuTypeId // .gpu_type_id // .gpu // .pod.gpuTypeId // "unknown" | tostring')"

  if ! ssh_info="$(runpodctl ssh info "$id" -o json 2>/dev/null)"; then
    return 0
  fi

  host="$(printf '%s\n' "$ssh_info" | runpod_ssh_host)"
  port="$(printf '%s\n' "$ssh_info" | runpod_ssh_port)"

  if [ -z "$host" ] || [ -z "$port" ]; then
    return 0
  fi

  jq -n -c \
    --arg provider "runpod" \
    --arg id "$id" \
    --arg gpu "$gpu" \
    --arg status "$status" \
    --arg user "root" \
    --arg host "$host" \
    --arg port "$port" \
    --arg label "$name" \
    '{provider: $provider, id: $id, gpu: $gpu, status: $status, user: $user, host: $host, port: $port, label: $label}'
}

runpod_candidates() {
  runpod_pod_rows | while IFS= read -r pod; do
    [ -n "$pod" ] && runpod_candidate_from_pod "$pod"
  done
}

ensure_runpod_key_registered() {
  local fp
  fp="$(ssh-keygen -lf "$SSH_KEY.pub" | awk '{print $2}')"

  if runpodctl ssh list-keys -o json |
    jq -e --arg fp "$fp" '(.keys // .) | if type == "array" then any(.[]; .fingerprint == $fp) else false end' >/dev/null; then
    return
  fi

  die "$SSH_KEY.pub is not registered with RunPod; run: runpodctl ssh add-key --key-file $SSH_KEY.pub before creating pods"
}

prime_pod_rows() {
  prime --plain pods list --output json |
    jq -c '(.pods // [])[]'
}

prime_candidate_from_pod() {
  local pod="$1"
  local id details ssh_value host_user user host port gpu status label

  id="$(printf '%s\n' "$pod" | jq -r '(.id // "") | tostring')"
  [ -n "$id" ] || return 0

  if ! details="$(prime --plain pods status "$id" --output json 2>/dev/null)"; then
    return 0
  fi

  ssh_value="$(printf '%s\n' "$details" | jq -r '(.ssh // "") | tostring | split(",")[0] | gsub("^ +| +$"; "")')"
  [ -n "$ssh_value" ] || return 0
  [ "$ssh_value" != "N/A" ] || return 0

  host_user="$ssh_value"
  port="22"
  if [[ "$ssh_value" == *" -p "* ]]; then
    host_user="${ssh_value%% -p *}"
    port="${ssh_value##* -p }"
    port="${port%% *}"
  fi

  if [[ "$host_user" == *@* ]]; then
    user="${host_user%@*}"
    host="${host_user#*@}"
  else
    user="ubuntu"
    host="$host_user"
  fi

  [ -n "$user" ] || return 0
  [ -n "$host" ] || return 0
  [ -n "$port" ] || return 0

  gpu="$(printf '%s\n' "$details" | jq -r '(.gpu // "unknown") | tostring')"
  status="$(printf '%s\n' "$details" | jq -r '(.status // "unknown") | tostring')"
  label="$(printf '%s\n' "$details" | jq -r '(.name // "") | tostring')"

  jq -n -c \
    --arg provider "prime" \
    --arg id "$id" \
    --arg gpu "$gpu" \
    --arg status "$status" \
    --arg user "$user" \
    --arg host "$host" \
    --arg port "$port" \
    --arg label "$label" \
    '{provider: $provider, id: $id, gpu: $gpu, status: $status, user: $user, host: $host, port: $port, label: $label}'
}

prime_candidates() {
  prime_pod_rows | while IFS= read -r pod; do
    [ -n "$pod" ] && prime_candidate_from_pod "$pod"
  done
}

is_valid_candidate() {
  jq -e '
    type == "object"
    and ((.provider // "") | tostring | length > 0)
    and ((.id // "") | tostring | length > 0)
    and ((.host // "") | tostring | length > 0)
    and ((.port // "") | tostring | length > 0)
  ' >/dev/null 2>&1
}

capture_candidates() {
  local provider="$1"
  local discover="$2"
  local stderr_file output row

  stderr_file="$(mktemp -t gpu-provision.XXXXXX)"
  if output="$("$discover" 2>"$stderr_file")"; then
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      if printf '%s\n' "$row" | is_valid_candidate; then
        printf '%s\n' "$row"
      else
        log "Ignoring non-candidate output from $provider discovery: $row"
      fi
    done <<<"$output"
  else
    log "$provider discovery failed:"
    while IFS= read -r row; do
      [ -n "$row" ] && log "$row"
    done <<<"$output"
    while IFS= read -r row; do
      [ -n "$row" ] && log "$row"
    done <"$stderr_file"
  fi
  rm -f "$stderr_file"
}

describe_candidate() {
  jq -r '[
    "provider=" + (.provider // "unknown"),
    "id=" + (.id // "unknown"),
    "gpu=" + (.gpu // "unknown"),
    "status=" + (.status // "unknown"),
    "ssh=" + (.user // "root") + "@" + (.host // "unknown") + ":" + (.port // "unknown"),
    "label=" + (.label // "")
  ] | join(" ")'
}

choose_from_candidates() {
  local candidates=("$@")

  case "${#candidates[@]}" in
    0)
      die "no running SSH-capable GPU hosts found"
      ;;
    1)
      printf '%s\n' "${candidates[0]}"
      ;;
    *)
      [ -t 0 ] || die "multiple GPU hosts found but stdin is not interactive"
      log "Multiple running GPU hosts found:"
      local i=1
      local row
      for row in "${candidates[@]}"; do
        printf '  %d) %s\n' "$i" "$(printf '%s\n' "$row" | describe_candidate)" >&2
        i=$((i + 1))
      done

      printf 'Choose host to set up: ' >&2
      local choice
      read -r choice
      case "$choice" in
        ''|*[!0-9]*)
          die "invalid choice: $choice"
          ;;
      esac
      if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#candidates[@]}" ]; then
        die "invalid choice: $choice"
      fi
      printf '%s\n' "${candidates[$((choice - 1))]}"
      ;;
  esac
}

select_candidate() {
  local candidates=()
  local output row

  if command -v vastai >/dev/null 2>&1; then
    output="$(capture_candidates "Vast" vast_candidates)"
    while IFS= read -r row; do
      [ -n "$row" ] && candidates+=("$row")
    done <<<"$output"
  else
    log "Skipping Vast discovery: vastai not found"
  fi

  if command -v runpodctl >/dev/null 2>&1; then
    output="$(capture_candidates "RunPod" runpod_candidates)"
    while IFS= read -r row; do
      [ -n "$row" ] && candidates+=("$row")
    done <<<"$output"
  else
    log "Skipping RunPod discovery: runpodctl not found"
  fi

  if command -v prime >/dev/null 2>&1; then
    output="$(capture_candidates "Prime" prime_candidates)"
    while IFS= read -r row; do
      [ -n "$row" ] && candidates+=("$row")
    done <<<"$output"
  else
    log "Skipping Prime discovery: prime not found"
  fi

  choose_from_candidates "${candidates[@]}"
}

update_ssh_config() {
  local candidate="$1"
  local provider user host port tmp
  provider="$(printf '%s\n' "$candidate" | jq -r '.provider')"
  user="$(printf '%s\n' "$candidate" | jq -r '.user // "root"')"
  host="$(printf '%s\n' "$candidate" | jq -r '.host')"
  port="$(printf '%s\n' "$candidate" | jq -r '.port')"

  [ -n "$user" ] || die "selected host has no SSH user"
  [ -n "$host" ] || die "selected host has no SSH host"
  [ -n "$port" ] || die "selected host has no SSH port"

  mkdir -p "$HOME/.ssh"
  touch "$HOME/.ssh/config"
  chmod 600 "$HOME/.ssh/config"
  tmp="$(mktemp)"

  awk -v alias="$HOST_ALIAS" '
    /^# BEGIN codex-gpu managed by (vast-setup|gpu-provision)[.]sh$/ { skip=1; next }
    /^# END codex-gpu managed by (vast-setup|gpu-provision)[.]sh$/ { skip=0; next }
    skip { next }
    $1 == "Host" && $2 == alias { skip_host=1; next }
    skip_host && $1 == "Host" { skip_host=0 }
    skip_host { next }
    { print }
  ' "$HOME/.ssh/config" >"$tmp"

  {
    cat "$tmp"
    printf '\n# BEGIN codex-gpu managed by gpu-provision.sh\n'
    printf 'Host %s\n' "$HOST_ALIAS"
    printf '  HostName %s\n' "$host"
    printf '  User %s\n' "$user"
    printf '  IdentityFile %s\n' "$SSH_KEY"
    printf '  IdentitiesOnly yes\n'
    printf '  Port %s\n' "$port"
    printf '  RequestTTY force\n'
    printf '  StrictHostKeyChecking accept-new\n'
    printf '# END codex-gpu managed by gpu-provision.sh\n'
  } >"$HOME/.ssh/config"

  rm -f "$tmp"
  log "Updated $HOST_ALIAS -> $provider $user@$host:$port"
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
  stage="$(mktemp -d -t gpu-provision.XXXXXX)"
  trap 'rm -rf "$stage"; trap - RETURN' RETURN

  COPYFILE_DISABLE=1 tar --no-xattrs \
    --exclude "$(basename "$DOTFILES_DIR")/.git/fsmonitor--daemon.ipc" \
    -czf "$stage/$(basename "$REMOTE_DOTFILES_ARCHIVE")" \
    -C "$(dirname "$DOTFILES_DIR")" \
    "$(basename "$DOTFILES_DIR")"
  cp "$DEPLOY_KEY" "$stage/$(basename "$REMOTE_DEPLOY_KEY")"
  cp "$GPU_SETUP" "$stage/$(basename "$REMOTE_GPU_SETUP")"
  scp "$stage/"* "$HOST_ALIAS:/tmp/"

  log "Running remote setup..."
  ssh -T "$HOST_ALIAS" \
    "REMOTE_DEPLOY_KEY='$REMOTE_DEPLOY_KEY' DOTFILES_ARCHIVE='$REMOTE_DOTFILES_ARCHIVE' bash '$REMOTE_GPU_SETUP'"
}

install_ghostty_terminfo() {
  require_command infocmp
  local ghostty_terminfo_dir="/Applications/Ghostty.app/Contents/Resources/terminfo"

  log "Installing Ghostty terminfo on remote..."
  if infocmp -x xterm-ghostty >/dev/null 2>&1; then
    infocmp -x xterm-ghostty | ssh -T "$HOST_ALIAS" 'mkdir -p ~/.terminfo && tic -x -o ~/.terminfo /dev/stdin'
  elif [ -d "$ghostty_terminfo_dir" ] && infocmp -A "$ghostty_terminfo_dir" -x xterm-ghostty >/dev/null 2>&1; then
    infocmp -A "$ghostty_terminfo_dir" -x xterm-ghostty | ssh -T "$HOST_ALIAS" 'mkdir -p ~/.terminfo && tic -x -o ~/.terminfo /dev/stdin'
  else
    die "local xterm-ghostty terminfo not found"
  fi
}

main() {
  [ "$#" -eq 0 ] || die "gpu-provision.sh does not accept arguments"
  check_common_prereqs
  ensure_codex_key_loaded

  local candidate
  candidate="$(select_candidate)"
  log "Selected $(printf '%s\n' "$candidate" | describe_candidate)"

  if [ "$(printf '%s\n' "$candidate" | jq -r '.provider')" = runpod ]; then
    ensure_runpod_key_registered
  fi

  update_ssh_config "$candidate"
  wait_for_ssh
  install_ghostty_terminfo
  run_remote_setup
  log "Done."
}

main "$@"
