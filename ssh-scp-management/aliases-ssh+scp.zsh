# ~/.aliases_ssh
# SSH/SCP alias system using CSV with dynamic function-based passthrough
# Requires: Zsh or Bash 4+ (associative arrays)
# Limitations: CSV parsing does not support quoted fields with embedded commas.

KEYPATH="${HOME}/.ssh"
DEFAULT_PORT=22
CSV_FILE="${HOME}/.ssh_hostmap.csv"

# Associative arrays for host data
declare -A SSH_HOSTS
declare -A SSH_KEYS
declare -A SSH_PORTS
declare -A SSH_COMMENTS
declare -A HEADER_MAP

# Parse CSV headers dynamically from a CSV file.
# Usage: parse_csv_headers [csv_file]
# Sets the HEADERS array variable and HEADER_MAP associative array.
parse_csv_headers() {
  local csv_file="${1:-$CSV_FILE}"
  local header_line
  local -a HEADERS

  # Check if file is specified and readable
  if [[ -z "$csv_file" ]]; then
    echo "Error: No CSV file specified." >&2
    return 1
  fi
  if [[ ! -r "$csv_file" ]]; then
    echo "Error: File '$csv_file' does not exist or is not readable." >&2
    return 2
  fi

  # Read the first line (header)
  header_line=$(head -n 1 "$csv_file" | tr -d '\r')
  if [[ -z "$header_line" ]]; then
    echo "Error: File '$csv_file' is empty or has no header." >&2
    return 3
  fi

  # NOTE: This simple split does not handle quoted headers with commas.
  IFS=',' read -r -a HEADERS <<< "$header_line"
  for i in "${!HEADERS[@]}"; do
    local header="${HEADERS[$i]// /}"  # remove spaces in header
    HEADER_MAP["$header"]="$i"
  done
  return 0
}

# Load all host definitions from CSV
parse_csv_rows() {
  local csv_file="${1:-$CSV_FILE}"
  if [[ ! -r "$csv_file" ]]; then
    echo "Error: File '$csv_file' does not exist or is not readable." >&2
    return 1
  fi

  tail -n +2 "$csv_file" | while IFS=',' read -r -a FIELDS; do
    # Trim whitespace from each field
    for i in "${!FIELDS[@]}"; do
      FIELDS[$i]="${FIELDS[$i]#"${FIELDS[$i]%%[![:space:]]*}"}"
      FIELDS[$i]="${FIELDS[$i]%"${FIELDS[$i]##*[![:space:]]}"}"
    done

    local label="${FIELDS[${HEADER_MAP[label]}]}"
    local sshuser="${FIELDS[${HEADER_MAP[sshuser]}]}"
    local host="${FIELDS[${HEADER_MAP[host]}]}"
    local keyfile="${FIELDS[${HEADER_MAP[keyfile]}]}"
    local port="${FIELDS[${HEADER_MAP[port]}]}"
    local comment="${FIELDS[${HEADER_MAP[comment]}]}"

    # Skip incomplete rows
    if [[ -z "$label" || -z "$sshuser" || -z "$host" || -z "$keyfile" ]]; then
      continue
    fi


    # Sanitize label for function name (alphanumeric and underscores only)
    local safe_label
    safe_label=$(echo "$label" | tr -cd '[:alnum:]_')
    if [[ -z "$safe_label" ]]; then
      echo "Warning: Skipping invalid label '$label'" >&2
      continue
    fi

    SSH_HOSTS["$safe_label"]="${sshuser}@${host}"
    SSH_KEYS["$safe_label"]="$keyfile"
    SSH_PORTS["$safe_label"]="${port:-$DEFAULT_PORT}"
    SSH_COMMENTS["$safe_label"]="$comment"

    # Define ssh-label() and scp-label() as shell functions with passthrough
    eval "ssh-$safe_label() { ssh_alias \"$safe_label\" \"\$@\"; }"
    eval "scp-$safe_label() { scp_alias \"$safe_label\" \"\$@\"; }"
  done
}

# SSH function
ssh_alias() {
  local label="$1"; shift
  local userhost="${SSH_HOSTS[$label]}"
  local port="${SSH_PORTS[$label]:-$DEFAULT_PORT}"
  local key="$KEYPATH/${SSH_KEYS[$label]}"

  if [[ -z "$userhost" || -z "$key" ]]; then
    echo "Error: Invalid label or missing key for '$label'" >&2
    return 1
  fi

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

  # Parse arguments
  while [[ $# -gt 0 ]]; do
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
    echo "Error: Invalid label '$label'" >&2
    return 1
  fi

  if [[ "$mode" == "to" ]]; then
    if [[ -z "$local_path" || -z "$remote_path" ]]; then
      echo "Error: --to requires --local and --remote" >&2
      return 1
    fi
    scp -P "$port" -i "$key" "$local_path" "$userhost:$remote_path"
  elif [[ "$mode" == "from" ]]; then
    if [[ -z "$local_path" || -z "$remote_path" ]]; then
      echo "Error: --from requires --local and --remote" >&2
      return 1
    fi
    scp -P "$port" -i "$key" "$userhost:$remote_path" "$local_path"
  else
    echo "Error: Must specify --to or --from" >&2
    return 1
  fi
}

# Start CSV parsing
if [[ -f "$CSV_FILE" ]]; then
  parse_csv_headers
  parse_csv_rows
else
  echo "Warning: SSH alias CSV not found at $CSV_FILE" >&2
fi

# Optional Zsh completion
if [[ -n "$ZSH_VERSION" ]]; then
  compdef _gnu_generic ssh_alias
  compdef _gnu_generic scp_alias
fi
