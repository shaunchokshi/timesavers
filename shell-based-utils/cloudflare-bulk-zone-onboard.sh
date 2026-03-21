#!/usr/bin/env bash
# cloudflare-bulk-zone-onboard.sh
# Bulk-onboard domains as full zones on Cloudflare's free plan via API.
#
# Usage:
#   export CLOUDFLARE_API_TOKEN="your_token_here"
#   export CLOUDFLARE_ACCOUNT_ID="your_account_id_here"
#   ./cloudflare-bulk-zone-onboard.sh
#
# Required permissions on the API token:
#   Zone → Zone → Edit   (or Zone DNS Edit)

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

API_TOKEN="${CLOUDFLARE_API_TOKEN:?Set CLOUDFLARE_API_TOKEN before running}"
ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:?Set CLOUDFLARE_ACCOUNT_ID before running}"
API_BASE="https://api.cloudflare.com/client/v4"
ZONE_TYPE="full"   # full = DNS hosted on Cloudflare (not partial/CNAME)
PLAN_LEGACY_ID="free"

# ---------------------------------------------------------------------------
# Domains to onboard — one per line
# ---------------------------------------------------------------------------

DOMAINS=(
  "example1.com"
  "example2.com"
  "example3.com"
  "example4.com"
  "example5.com"
  "example6.com"
  "example7.com"
  "example8.com"
  "example9.com"
  "example10.com"
  "example11.com"
  "example12.com"
  "example13.com"
  "example14.com"
  "example15.com"
  "example16.com"
  "example17.com"
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
log_err()  { echo -e "${RED}[FAIL]${NC}  $*"; }
log_info() { echo -e "${YELLOW}[INFO]${NC}  $*"; }

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

TOTAL=${#DOMAINS[@]}
SUCCESS=0
FAILED=0
SKIPPED=0

echo "============================================================"
echo " Cloudflare bulk zone onboarding — ${TOTAL} domains"
echo " Account : ${ACCOUNT_ID}"
echo " Type    : ${ZONE_TYPE}  |  Plan: ${PLAN_LEGACY_ID}"
echo "============================================================"
echo

for DOMAIN in "${DOMAINS[@]}"; do

  # Skip blank lines / accidental whitespace
  DOMAIN="$(echo "${DOMAIN}" | tr -d '[:space:]')"
  [[ -z "${DOMAIN}" ]] && continue

  log_info "Adding ${DOMAIN} ..."

  RESPONSE=$(curl --silent --show-error \
    --request POST "${API_BASE}/zones" \
    --header "Content-Type: application/json" \
    --header "Authorization: Bearer ${API_TOKEN}" \
    --data "$(jq -n \
      --arg name    "${DOMAIN}" \
      --arg type    "${ZONE_TYPE}" \
      --arg acct_id "${ACCOUNT_ID}" \
      '{account: {id: $acct_id}, name: $name, type: $type}'
    )"
  )

  SUCCESS_FIELD=$(echo "${RESPONSE}" | jq -r '.success')

  if [[ "${SUCCESS_FIELD}" == "true" ]]; then
    ZONE_ID=$(echo "${RESPONSE}"      | jq -r '.result.id')
    NS=$(echo "${RESPONSE}"           | jq -r '.result.name_servers | join(", ")')
    STATUS=$(echo "${RESPONSE}"       | jq -r '.result.status')
    log_ok "${DOMAIN}  →  zone_id=${ZONE_ID}  status=${STATUS}"
    log_ok "          nameservers: ${NS}"
    (( SUCCESS++ )) || true
  else
    ERR_CODE=$(echo "${RESPONSE}"    | jq -r '.errors[0].code    // "unknown"')
    ERR_MSG=$(echo "${RESPONSE}"     | jq -r '.errors[0].message // "unknown"')
    # 1049 = zone already exists; treat as a skip rather than hard failure
    if [[ "${ERR_CODE}" == "1049" ]]; then
      log_info "${DOMAIN}  →  already exists in Cloudflare (skipping)"
      (( SKIPPED++ )) || true
    else
      log_err "${DOMAIN}  →  code=${ERR_CODE}  message=${ERR_MSG}"
      (( FAILED++ )) || true
    fi
  fi

  echo

done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo "============================================================"
echo " Results: ${SUCCESS} added  |  ${SKIPPED} already existed  |  ${FAILED} failed"
echo "============================================================"

[[ ${FAILED} -eq 0 ]]   # exit non-zero if any hard failures
