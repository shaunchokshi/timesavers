#!/usr/bin/env bash
# load_b2_env.sh
# Detect host, source the correct Backblaze B2 env file,
# export B2_KEY_ID and B2_APP_KEY.

set -euo pipefail

# --- Identify this host ---
HOSTNAME="$(hostname 2>/dev/null || uname -n)"
# Normalize for safety (strip whitespace, lowercase)
HOSTNAME="$(echo "$HOSTNAME" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]//g')"

# --- Base path where your host-specific env files live ---
# e.g. /etc/b2-env or ~/.config/b2-env
ENV_DIR="${HOME}/.config/b2-env"

# Ensure directory exists
if [ ! -d "$ENV_DIR" ]; then
    echo "Error: ENV_DIR '$ENV_DIR' does not exist." >&2
    exit 1
fi

# --- Decide which .env file to use ---
# Example hostnames:
#  x6       => .env.x6
#  p370-c   => .env.P370-C (but we normalize lowercase)
#  fallback => .env.default

if [ "$HOSTNAME" = "x6" ]; then
    ENV_FILE="${ENV_DIR}/.env.x6"
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
