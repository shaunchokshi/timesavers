#!/usr/bin/env bash
# b2_multi-bucket_manager.sh
# Backblaze B2 multi-bucket backup + sync manager with client-side encryption,
# 96-hour version retention, and a "sync island" for async device coordination.





# ====== PREREQS ===============================================================
# - rclone v1.57+ recommended (B2 + crypt). Install from https://rclone.org/downloads/
# - Backblaze B2 Application Key ID and Application Key (env vars or prompt).
# - Buckets should exist already (script can create remotes; creating buckets is optional here).


# incorporate load_b2_env.sh
# Detect host, source the correct Backblaze B2 env file,

###
### # ENV FILE TEMPLATE
### # put this file labeled as '.env.${hostame}'
### # in path '${HOME}/.secrets/.env.${hostname}'
### # ```
###
### B2_KEY_ID=
### B2_APP_KEY=
###
### # ```
###

# export B2_KEY_ID and B2_APP_KEY.

set -euo pipefail

# --- Identify this host ---
HOSTNAME="$(hostname -s 2>/dev/null || uname -n)"
# Normalize for safety (strip whitespace, lowercase)
HOSTNAME="$(echo "$HOSTNAME" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]//g')"

# --- Base path where your host-specific env files live ---
# e.g. /etc/b2-env or ~/.config/b2-env
ENV_DIR="${HOME}/.secrets"

# Ensure directory exists
if [ ! -d "$ENV_DIR" ]; then
    echo "Error: ENV_DIR '$ENV_DIR' does not exist." >&2
    exit 1
fi

# --- Decide which .env file to use ---
# Example hostnames:
#  X6-79    => .env.X6-79
#  P370-C   => .env.P370-C
#  mbp4m    => .env.mbp4m (this might have to be .env.mbp4m.local
#  fallback => .env.default

if [ "$HOSTNAME" = "x6" ]; then
    ENV_FILE="${ENV_DIR}/.env.X6-79"
elif [ "$HOSTNAME" = "p370-c" ]; then
    ENV_FILE="${ENV_DIR}/.env.P370-C"
elif [ "$HOSTNAME" = "r720-node1" ]; then
    ENV_FILE="${ENV_DIR}/.env.r720-node1"
else
    ENV_FILE="${ENV_DIR}/.env.default"
fi

# --- Source the env file ---
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: Expected env file not found: $ENV_FILE" >&2
    exit 1
fi

# shellcheck source=/dev/null
. "$ENV_FILE"

# --- Validate required vars ---
: "${B2_KEY_ID:?Missing B2_KEY_ID in $ENV_FILE}"
: "${B2_APP_KEY:?Missing B2_APP_KEY in $ENV_FILE}"

export B2_KEY_ID B2_APP_KEY

# Optional: print confirmation (comment out in prod)
echo "Loaded Backblaze env for host '$HOSTNAME' from '$ENV_FILE'"



# B2 credentials: prefer env vars for security; will prompt if absent
: "${B2_KEY_ID:=${B2_KEY_ID:-}}"
: "${B2_APP_KEY:=${B2_APP_KEY:-}}"

# Buckets:
# One encrypted bucket PER host for backups (name by host), plus one "sync island" bucket.
# Example: backups: host-a-backups (encrypted), host-b-backups (encrypted)
#          sync: my-sync-island (can be encrypted or not)
BACKUP_BUCKETS=("host-a-backups" "host-b-backups")  # add/remove as needed
SYNC_BUCKET="my-sync-island"

# Choose whether SYNC bucket uses client-side encryption via rclone crypt.
SYNC_BUCKET_ENCRYPTED=true

# rclone remote names we’ll create/use:
BASE_REMOTE_NAME="b2raw"     # points to Backblaze B2 (unencrypted)
CRYPT_REMOTE_NAME="b2crypt"  # crypt overlay for encrypted buckets

# What to backup per host (local -> bucket). Define per-run using prompts OR static map below.
# We’ll prompt for a source path each time; you can hardcode pairs if you prefer.

# Retention window for versioned changes (rollback window)
RETENTION_HOURS=96

# Default region placeholder (B2 doesn’t need AWS regions; keep for symmetry)
B2_ENDPOINT=""  # usually blank for Backblaze; rclone handles endpoints automatically

# Performance knobs (tune safely)
TRANSFERS=8
CHECKERS=16

# ====== UTILITIES ==============================================================

timestamp_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

ensure_rclone() {
  if ! command -v rclone >/dev/null 2>&1; then
    echo "Error: rclone not found. Install rclone and re-run." >&2
    exit 1
  fi
}

prompt_if_empty() {
  local var_name="$1"
  local prompt="$2"
  local -n ref="$var_name"
  if [[ -z "${ref}" ]]; then
    read -r -p "$prompt" ref
  fi
}

# Create or refresh rclone remotes for B2 and Crypt overlay
ensure_rclone_remotes() {
  # Base B2 remote
  if ! rclone config show "${BASE_REMOTE_NAME}" >/dev/null 2>&1; then
    echo "Creating rclone remote '${BASE_REMOTE_NAME}' for Backblaze B2..."
    rclone config create "${BASE_REMOTE_NAME}" b2 account "${B2_KEY_ID}" key "${B2_APP_KEY}" >/dev/null
  fi

  # Crypt overlay (client-side encryption). Uses per-bucket password/salt from env or interactive.
  # You can share one crypt across buckets; rclone crypt will encrypt object names + data.
  if ! rclone config show "${CRYPT_REMOTE_NAME}" >/dev/null 2>&1; then
    echo "Creating rclone crypt remote '${CRYPT_REMOTE_NAME}'..."
    echo "For best security, set env vars RCLONE_CRYPT_PASSWORD and RCLONE_CRYPT_PASSWORD2."
    : "${RCLONE_CRYPT_PASSWORD:=${RCLONE_CRYPT_PASSWORD:-}}"
    : "${RCLONE_CRYPT_PASSWORD2:=${RCLONE_CRYPT_PASSWORD2:-}}"

    if [[ -z "${RCLONE_CRYPT_PASSWORD}" ]]; then
      read -rs -p "Enter rclone crypt password (RCLONE_CRYPT_PASSWORD): " RCLONE_CRYPT_PASSWORD; echo
    fi
    if [[ -z "${RCLONE_CRYPT_PASSWORD2}" ]]; then
      read -rs -p "Enter rclone crypt salt (RCLONE_CRYPT_PASSWORD2): " RCLONE_CRYPT_PASSWORD2; echo
    fi

    # Create crypt remote; the 'remote' field will be set dynamically per bucket.
    # We create a "template" remote pointed at base for now; we'll pass full
    # "b2crypt:bucket" paths at runtime so we can reuse one config.
    rclone config create "${CRYPT_REMOTE_NAME}" crypt \
      remote "${BASE_REMOTE_NAME}:" \
      password "${RCLONE_CRYPT_PASSWORD}" password2 "${RCLONE_CRYPT_PASSWORD2}" >/dev/null
  fi
}

# Build a remote path like:
#   encrypted backups:   b2crypt:bucket-name/...
#   unencrypted backups: b2raw:bucket-name/...
remote_path_for_bucket() {
  local bucket="$1"
  local encrypted="$2"
  if [[ "${encrypted}" == "true" ]]; then
    printf "%s:%s" "${CRYPT_REMOTE_NAME}" "${bucket}"
  else
    printf "%s:%s" "${BASE_REMOTE_NAME}" "${bucket}"
  fi
}

# Back up a local folder to an encrypted bucket with versioning (differential)
# We keep changed/deleted files in --backup-dir with ISO timestamp
backup_folder_to_bucket() {
  local source_dir="$1"
  local bucket="$2"
  local encrypted="true"

  local now; now="$(timestamp_iso)"
  local remote_root; remote_root="$(remote_path_for_bucket "${bucket}" "${encrypted}")"
  local backup_dir="${remote_root}/.versions/${now}"

  echo "Backing up '${source_dir}' -> '${remote_root}'"
  echo "Versioned changes will be stored under '${backup_dir}' (retained ${RETENTION_HOURS}h)."

  rclone sync "${source_dir}" "${remote_root}" \
    --backup-dir "${backup_dir}" \
    --transfers "${TRANSFERS}" --checkers "${CHECKERS}" \
    --fast-list \
    --b2-hard-delete=false \
    --delete-excluded \
    --exclude ".versions/**" \
    --log-file "backup_${bucket}_$(date -u +%Y-%m-%dT%H:%M:%SZ).log" \
    --log-level INFO

  # Retention: remove version folders older than RETENTION_HOURS
  # Use rclone delete with --min-age to target old objects in .versions/
  rclone delete "${remote_root}/.versions" --min-age "${RETENTION_HOURS}h" --fast-list \
    --log-level NOTICE || true
  rclone rmdirs "${remote_root}/.versions" --leave-root --log-level NOTICE || true

  echo "Backup complete for bucket '${bucket}'."
}

# Sync island: keeps a common folder in sync across devices
# If encrypted, same crypt overlay; versions kept for RETENTION_HOURS
sync_island() {
  local source_dir="$1"
  local bucket="${SYNC_BUCKET}"
  local encrypted="${SYNC_BUCKET_ENCRYPTED}"

  local now; now="$(timestamp_iso)"
  local remote_root; remote_root="$(remote_path_for_bucket "${bucket}" "${encrypted}")"
  local backup_dir="${remote_root}/.versions/${now}"

  echo "Syncing 'island' '${source_dir}' -> '${remote_root}' (encrypted: ${encrypted})"
  rclone sync "${source_dir}" "${remote_root}" \
    --backup-dir "${backup_dir}" \
    --transfers "${TRANSFERS}" --checkers "${CHECKERS}" \
    --fast-list \
    --b2-hard-delete=false \
    --delete-excluded \
    --exclude ".versions/**" \
    --log-file "sync_island_$(date -u +%Y-%m-%dT%H:%M:%SZ).log" \
    --log-level INFO

  # Retention cleanup for island versions
  rclone delete "${remote_root}/.versions" --min-age "${RETENTION_HOURS}h" --fast-list \
    --log-level NOTICE || true
  rclone rmdirs "${remote_root}/.versions" --leave-root --log-level NOTICE || true

  echo "Sync island complete."
}

# ====== MAIN ================================================================

main() {
  ensure_rclone

  # Gather B2 credentials
  prompt_if_empty B2_KEY_ID "Enter B2 Application Key ID: "
  prompt_if_empty B2_APP_KEY "Enter B2 Application Key (will not be echoed on a secure terminal): "
  export B2_KEY_ID B2_APP_KEY

  ensure_rclone_remotes

  # --- Choose action ---
  echo
  echo "Select an action:"
  echo "  1) Backup a folder to one of the encrypted BACKUP buckets"
  echo "  2) Sync a folder to the SYNC ISLAND bucket (encrypted=${SYNC_BUCKET_ENCRYPTED})"
  echo "  3) Exit"
  read -r -p "Enter choice [1-3]: " choice

  case "${choice}" in
    1)
      # pick a backup bucket
      echo "Available backup buckets:"
      local idx=0
      for b in "${BACKUP_BUCKETS[@]}"; do
        echo "  [$idx] $b"
        ((idx++))
      done
      read -r -p "Choose bucket index: " bidx
      if ! [[ "$bidx" =~ ^[0-9]+$ ]] || (( bidx < 0 || bidx >= ${#BACKUP_BUCKETS[@]} )); then
        echo "Invalid index." >&2
        exit 1
      fi
      local bucket="${BACKUP_BUCKETS[$bidx]}"

      # pick source path using your preferred interactive style
      SEARCH_PATH="$(pwd)"
      read -e -i "$SEARCH_PATH" -p "Enter local path to BACKUP: " SEARCH_PATH
      local src="${SEARCH_PATH%/}"
      if [[ ! -d "$src" ]]; then
        echo "Error: not a directory: $src" >&2
        exit 1
      fi

      backup_folder_to_bucket "$src" "$bucket"
      ;;

    2)
      # pick source for sync island
      SEARCH_PATH="$(pwd)"
      read -e -i "$SEARCH_PATH" -p "Enter local folder to SYNC to island: " SEARCH_PATH
      local src="${SEARCH_PATH%/}"
      if [[ ! -d "$src" ]]; then
        echo "Error: not a directory: $src" >&2
        exit 1
      fi
      sync_island "$src"
      ;;

    3) echo "Bye."; exit 0 ;;
    *) echo "Unknown choice." >&2; exit 1 ;;
  esac
}

main "$@"
