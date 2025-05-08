# A more dynamic use approach to aliases for SSH and SCP

## Uses function definitions instead of aliases

    - Loads host definitions from a flexible CSV file (column order doesn't matter)

    - Uses function-based definitions like ssh-web and scp-db that pass along all extra arguments

    - No need to hard-code options for one-off/edge cases of ssh/scp (e.g. Xsession forwarding sometimes)

    - Handles optional ports, key files, and user@host formatting (aliases cannot handle all options passed via stdin)

    -- Example alias: ```alias ssh-samplehost='ssh -i ~/.ssh/example.key user@hostname'```
    -- If you sometimes need to have Xsession forwarding with that host... ```ssh-web -X``` will not work (it won't add the +X option to the command that the alias is invoking)

    - Is shell-compatible with both Bash and Zsh

    -

### script

<!-- trunk-ignore(markdownlint/MD046) -->
```shell
# save as ~/.aliases_ssh or $ZSH_CUSTOM/
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

```

### sample CSV file `.ssh_hostmap.csv` (with flexible column order)
<!-- trunk-ignore(markdownlint/MD046) -->
```csv
host,label,sshuser,keyfile,port,comment
web.example.com,web,user1,id_rsa_web,2222,Main web server
db.example.com,db,admin,id_ed25519_db,2022,Database access
backup.example.com,backup,user2,id_rsa_backup,,Default port
db.example.com,root-db,root,id_ed25519_db,2022,Root DB login
```

### Usage
<!-- trunk-ignore(markdownlint/MD046) -->
```shell
# SSH as usual
ssh-web
ssh-db -X
ssh-root-db -L 9000:localhost:5432

# SCP to/from
scp-db --to --local=./file.txt --remote=/tmp/
scp-backup --from --remote=/etc/nginx/nginx.conf --local=./
```

## Here's a quick script that interactively allows you to add new hosts to the hostmap
<!-- trunk-ignore(markdownlint/MD046) -->
```shell
#!/usr/bin/env bash

CSV_FILE="$HOME/.ssh_hostmap.csv"
KEYPATH_DEFAULT="$HOME/.ssh"
DEFAULT_PORT=22

# Check if the CSV file exists; if not, create it with header
if [[ ! -f "$CSV_FILE" ]]; then
  echo "label,sshuser,host,keyfile,port,comment" > "$CSV_FILE"
  echo "Created new CSV file at $CSV_FILE"
fi

echo "=== Add a New SSH Host Entry ==="
read -rp "Label (used in ssh-[label] / scp-[label]): " label
read -rp "SSH Username: " sshuser
read -rp "Hostname or IP: " host
read -rp "Key filename (in $KEYPATH_DEFAULT): " keyfile
read -rp "Port (default is $DEFAULT_PORT): " port
read -rp "Comment or description (optional): " comment

# Strip commas to avoid breaking CSV format
label="${label//,/}"
sshuser="${sshuser//,/}"
host="${host//,/}"
keyfile="${keyfile//,/}"
port="${port//,/}"
comment="${comment//,/}"

# Default port if blank
if [[ -z "$port" ]]; then
  port="$DEFAULT_PORT"
fi

# Confirm entry
echo
echo "📝 New Entry:"
printf "  %-8s : %s\n" "Label" "$label"
printf "  %-8s : %s\n" "User" "$sshuser"
printf "  %-8s : %s\n" "Host" "$host"
printf "  %-8s : %s\n" "Key" "$keyfile"
printf "  %-8s : %s\n" "Port" "$port"
printf "  %-8s : %s\n" "Comment" "$comment"
echo

read -rp "Add this entry to $CSV_FILE? (y/n): " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
  echo "$label,$sshuser,$host,$keyfile,$port,$comment" >> "$CSV_FILE"
  echo "✅ Added."
else
  echo "❌ Cancelled."
fi
```

### How to use the script

- Save the script to some place in your $PATH (e.g. ~/.local/bin/csv-add-host)
- Make it executable `chmod +x ~/.local/bin/csv-add-host`
- You can check that `/home/user/.local/bin` is in your $PATH `echo $PATH`
- Add it to the path if it is not `export PATH="$HOME/.local/bin:$PATH"`
- after that, run it `csv-add-host` and follow the prompts
