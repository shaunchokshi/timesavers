# ~/.aliases_ssh
# SSH/SCP alias system using CSV with dynamic function-based passthrough

KEYPATH="$HOME/.ssh"
DEFAULT_PORT=22
CSV_FILE="$HOME/sample.ssh_hostmap.csv"

# Associative arrays for host data
declare -A SSH_HOSTS
declare -A SSH_KEYS
declare -A SSH_PORTS
declare -A SSH_COMMENTS

# Parse CSV headers dynamically
parse_csv_headers() {
  IFS=',' read -r -a HEADERS <<< "$(head -n 1 "$CSV_FILE" | tr -d '\r')"
  for i in "${!HEADERS[@]}"; do
    header="${HEADERS[$i]// /}"  # remove spaces in header
    HEADER_MAP["$header"]="$i"
  done
}

# Load all host definitions from CSV
parse_csv_rows() {
  tail -n +2 "$CSV_FILE" | while IFS=',' read -r -a FIELDS; do
    for i in "${!FIELDS[@]}"; do
      FIELDS[$i]=$(echo "${FIELDS[$i]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    done

    local label="${FIELDS[${HEADER_MAP[label]}]}"
    local sshuser="${FIELDS[${HEADER_MAP[sshuser]}]}"
    local host="${FIELDS[${HEADER_MAP[host]}]}"
    local keyfile="${FIELDS[${HEADER_MAP[keyfile]}]}"
    local port="${FIELDS[${HEADER_MAP[port]}]}"
    local comment="${FIELDS[${HEADER_MAP[comment]}]}"

    [[ -z "$label" || -z "$sshuser" || -z "$host" || -z "$keyfile" ]] && continue

    SSH_HOSTS["$label"]="${sshuser}@${host}"
    SSH_KEYS["$label"]="$keyfile"
    SSH_PORTS["$label"]="${port:-$DEFAULT_PORT}"
    SSH_COMMENTS["$label"]="$comment"

    # Define ssh-label() as a shell function with passthrough
    eval "ssh-$label() { ssh_alias \"$label\" \"\$@\"; }"
    eval "scp-$label() { scp_alias \"$label\" \"\$@\"; }"
  done
}

# SSH function
ssh_alias() {
  local label="$1"; shift
  local userhost="${SSH_HOSTS[$label]}"
  local port="${SSH_PORTS[$label]:-$DEFAULT_PORT}"
  local key="$KEYPATH/${SSH_KEYS[$label]}"

  ssh -p "$port" -i "$key" "$@" "$userhost"
}

# SCP function with --to and --from flags
scp_alias() {
  local mode=""
  local local_path=""
  local remote_path=""
  local label=""
  local userhost=""
  local port=""
  local key=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --to) mode="to"; shift ;;
      --from) mode="from"; shift ;;
      --local=*) local_path="${1#*=}"; shift ;;
      --remote=*) remote_path="${1#*=}"; shift ;;
      *) label="$1"; shift ;;
    esac
  done

  userhost="${SSH_HOSTS[$label]}"
  port="${SSH_PORTS[$label]:-$DEFAULT_PORT}"
  key="$KEYPATH/${SSH_KEYS[$label]}"

  if [[ -z "$userhost" || -z "$key" ]]; then
    echo "Invalid label: '$label'" >&2
    return 1
  fi

  if [[ "$mode" == "to" ]]; then
    scp -P "$port" -i "$key" "$local_path" "$userhost:$remote_path"
  elif [[ "$mode" == "from" ]]; then
    scp -P "$port" -i "$key" "$userhost:$remote_path" "$local_path"
  else
    echo "Error: Must specify --to or --from"
    return 1
  fi
}

# Start CSV parsing
declare -A HEADER_MAP
if [[ -f "$CSV_FILE" ]]; then
  parse_csv_headers
  parse_csv_rows
else
  echo "Warning: SSH alias CSV not found at $CSV_FILE"
fi

# Optional Zsh completion
if [[ -n "$ZSH_VERSION" ]]; then
  compdef _gnu_generic ssh_alias
  compdef _gnu_generic scp_alias
fi
