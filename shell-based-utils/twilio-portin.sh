#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Twilio Porting CLI (Public Beta APIs)
# Requirements: bash, curl, python3
# Optional: jq
###############################################################################

# --------------------------- UI helpers --------------------------------------

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[!]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[+]\033[0m %s\n" "$*"; }

confirm_yn() {
  local prompt="$1"
  local default="${2:-y}"  # y/n
  local ans=""
  while true; do
    if [[ "$default" == "y" ]]; then
      read -r -p "${prompt} [Y/n]: " ans
      ans="${ans:-Y}"
    else
      read -r -p "${prompt} [y/N]: " ans
      ans="${ans:-N}"
    fi
    case "${ans,,}" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *) warn "Please answer y or n." ;;
    esac
  done
}

confirm_value() {
  local label="$1"
  local value="$2"
  echo ""
  bold "${label}:"
  printf "  %s\n" "$value"
  confirm_yn "Confirm this is correct?" "y"
}

# User preference: interactive path prompt with read -e -i
prompt_path() {
  local prompt="$1"
  local default_path="$2"
  local varname="$3"
  local input=""
  SEARCH_PATH="$default_path"
  read -e -i "$SEARCH_PATH" -p "$prompt" input
  printf -v "$varname" "%s" "$input"
}

# ---------------------- Timestamp + logging ----------------------------------

LOG_STARTED=0
LOG_FILE=""

iso_ts() {
  # Produces something like: 2025-12-21T12:34:56-05:00
  # macOS date gives -0500; we insert colon.
  local raw
  raw="$(date +%Y-%m-%dT%H:%M:%S%z)"   # e.g., 2025-12-21T12:34:56-0500
  printf "%s\n" "$raw" | sed -E 's/([+-][0-9]{2})([0-9]{2})$/\1:\2/'
}

safe_ts_for_filename() {
  # Replace ':' with '' for filename safety; keep offset with '-0500' style
  # Example: 2025-12-21T12-34-56-05-00
  iso_ts | sed 's/:/-/g'
}

start_logging_if_needed() {
  if [[ "$LOG_STARTED" -eq 1 ]]; then
    return 0
  fi

  local ts
  ts="$(safe_ts_for_filename)"
  LOG_FILE="twilio_porting_run_${ts}.log"

  # Redirect stdout+stderr through tee into log file.
  exec > >(tee -a "$LOG_FILE") 2>&1
  LOG_STARTED=1

  echo ""
  bold "Logging enabled"
  echo "Log file: ${LOG_FILE}"
  echo "Run timestamp: $(iso_ts)"
  echo ""
}

# ---------------------- Phone normalization -----------------------------------

normalize_us_10_digits() {
  local raw="$1"
  local digits
  digits="$(printf "%s" "$raw" | tr -cd '0-9')"

  if [[ "${#digits}" -eq 11 && "${digits:0:1}" == "1" ]]; then
    digits="${digits:1:10}"
  fi

  if [[ "${#digits}" -ne 10 ]]; then
    printf ""
    return 1
  fi
  printf "%s" "$digits"
  return 0
}

format_e164_us() {
  local ten="$1"
  printf "+1%s" "$ten"
}

urlencode_plus_e164() {
  local e164="$1"
  printf "%s" "${e164/+/%2B}"
}

# ---------------------- Reason code table -------------------------------------

declare -A PORTABILITY_REASON_NAME=(
  ["22131"]="ALREADY_IN_THE_TARGET_ACCOUNT"
  ["22132"]="ALREADY_IN_TWILIO_DIFFERENT_OWNER"
  ["22136"]="ALREADY_IN_ONE_OF_YOUR_TWILIO_ACCOUNTS"
  ["22130"]="UNSUPPORTED"
  ["22133"]="MANUAL_PORTING_AVAILABLE"
  ["22102"]="INVALID_PHONE_NUMBER"
  ["22171"]="MISSING_REQUIRED_FIELDS"
  ["22135"]="ERROR_INTERNAL_SERVER_ERROR"
  ["20003"]="UNAUTHORIZED"
)

declare -A PORTABILITY_REASON_DESC=(
  ["22131"]="Number already exists on your Twilio account or is currently being ported into your account."
  ["22132"]="Number exists on another Twilio account (different owner)."
  ["22136"]="Number exists in one of your Twilio accounts or is currently being ported into one of them."
  ["22130"]="Number is in a country/rate center/carrier Twilio doesn’t support for porting via API."
  ["22133"]="Not portable via Porting API; manual porting is available (Console/Support depending on country)."
  ["22102"]="E.164 format required (e.g., +14155552344)."
  ["22171"]="Additional required fields missing for this number/flow."
  ["22135"]="Internal error determining portability; try again."
  ["20003"]="Unauthorized: account not valid or no access to TargetAccountSid."
)

explain_reason_code() {
  local code="$1"
  local name="${PORTABILITY_REASON_NAME[$code]:-UNKNOWN_CODE}"
  local desc="${PORTABILITY_REASON_DESC[$code]:-No description available in the local table.}"
  echo ""
  bold "Portability reason code: ${code}"
  printf "  %s\n" "$name"
  printf "  %s\n" "$desc"
  echo ""
}

# ---------------------- JSON helpers ------------------------------------------

have_jq() { command -v jq >/dev/null 2>&1; }

pretty_print_json() {
  local json="$1"
  if have_jq; then
    printf "%s\n" "$json" | jq .
  else
    python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), indent=2))' <<<"$json" 2>/dev/null || printf "%s\n" "$json"
  fi
}

json_get() {
  local json="$1"
  local key="$2"
  python3 -c 'import json,sys; obj=json.loads(sys.argv[1]); print(obj.get(sys.argv[2]) if obj.get(sys.argv[2]) is not None else "")' \
    "$json" "$key"
}

# ---------------------- Email input -------------------------------------------

collect_notification_emails() {
  # Default list
  local defaults="shaun@chokshi.net,shaun@ckservicesllc.com"
  local input=""
  read -r -p "notification_emails (comma-separated) [default: ${defaults}]: " input
  input="${input:-$defaults}"

  # Normalize: split, trim, drop empties
  local normalized
  normalized="$(python3 -c '
import sys
raw=sys.argv[1]
parts=[p.strip() for p in raw.split(",")]
parts=[p for p in parts if p]
print(",".join(parts))
' "$input")"

  if ! confirm_value "notification_emails (normalized)" "$normalized"; then
    echo ""
    warn "Re-enter notification emails."
    collect_notification_emails
    return
  fi

  printf "%s" "$normalized"
}

emails_csv_to_json_array() {
  local csv="$1"
  python3 -c '
import json,sys
csv=sys.argv[1].strip()
arr=[x.strip() for x in csv.split(",") if x.strip()]
print(json.dumps(arr))
' "$csv"
}

# ---------------------- Auth handling -----------------------------------------

AUTH_USER=""
AUTH_PASS=""
AUTH_MODE=""

get_auth() {
  echo ""
  bold "Authentication"
  echo "Recommended: API Key + API Key Secret (scoped permissions)."
  echo "Alternative: Account SID + Auth Token (global / broader permissions)."
  echo ""

  local choice=""
  while true; do
    read -r -p "Choose auth method: [1] API Key  [2] Account SID/Auth Token : " choice
    case "$choice" in
      1)
        AUTH_MODE="api_key"
        read -r -p "Enter API Key (username): " AUTH_USER
        read -r -s -p "Enter API Key Secret (password): " AUTH_PASS; echo ""
        confirm_value "API Key (username)" "$AUTH_USER" || continue
        confirm_yn "Confirm API Key Secret was entered correctly?" "y" || continue
        break
        ;;
      2)
        AUTH_MODE="account_token"
        read -r -p "Enter Account SID (username): " AUTH_USER
        read -r -s -p "Enter Auth Token (password): " AUTH_PASS; echo ""
        confirm_value "Account SID (username)" "$AUTH_USER" || continue
        confirm_yn "Confirm Auth Token was entered correctly?" "y" || continue
        break
        ;;
      *)
        warn "Enter 1 or 2."
        ;;
    esac
  done
}

# ---------------------- HTTP helpers ------------------------------------------

curl_json() {
  local method="$1"
  local url="$2"
  local data="${3:-}"

  if [[ -n "$data" ]]; then
    curl --silent --show-error --location \
      -X "$method" "$url" \
      -u "${AUTH_USER}:${AUTH_PASS}" \
      -H "Content-Type: application/json" \
      --data-raw "$data"
  else
    curl --silent --show-error --location \
      -X "$method" "$url" \
      -u "${AUTH_USER}:${AUTH_PASS}" \
      -H "Content-Type: application/json"
  fi
}

# ---------------------- Operations --------------------------------------------

op_portability_check() {
  bold "Portability check (US +1, normalize to 10 digits)"
  get_auth

  local target_account_sid=""
  read -r -p "Enter target Account SID (usually your Account SID): " target_account_sid
  confirm_value "TargetAccountSid" "$target_account_sid" || { warn "Cancelled."; return; }

  local raw_phone=""
  read -r -p "Enter US phone number (any format): " raw_phone

  local ten=""
  ten="$(normalize_us_10_digits "$raw_phone")" || { err "Invalid phone number. Need 10 digits (or 11 starting with 1)."; return; }

  local e164
  e164="$(format_e164_us "$ten")"
  confirm_value "Normalized phone number (E.164)" "$e164" || { warn "Cancelled."; return; }

  local encoded
  encoded="$(urlencode_plus_e164 "$e164")"

  local url="https://numbers.twilio.com/v1/Porting/Portability/PhoneNumber/${encoded}?TargetAccountSid=${target_account_sid}"

  echo ""
  bold "Request preview:"
  printf "  GET %s\n" "$url"

  confirm_yn "Send request now?" "y" || { warn "Cancelled."; return; }

  # Only start logging when we actually attempt an API call
  start_logging_if_needed

  local resp
  resp="$(curl_json "GET" "$url")"

  echo ""
  bold "Response:"
  pretty_print_json "$resp"

  local portable
  portable="$(json_get "$resp" "portable")"

  if [[ "$portable" == "True" || "$portable" == "true" ]]; then
    ok "portable=true (number can be ported via API)"
  elif [[ "$portable" == "False" || "$portable" == "false" ]]; then
    warn "portable=false (cannot be ported via API)"
    local code
    code="$(json_get "$resp" "not_portable_reason_code")"
    [[ -n "$code" ]] && explain_reason_code "$code"
  else
    warn "Could not interpret 'portable' field (might be an error response)."
    local maybe_code
    maybe_code="$(json_get "$resp" "code")"
    [[ -n "$maybe_code" ]] && warn "Error code in response: $maybe_code"
  fi
}

upload_document_utility_bill() {
  local pdf_path="$1"
  local friendly_name="$2"

  [[ -f "$pdf_path" ]] || { err "File not found: $pdf_path"; return 1; }

  local url="https://numbers-upload.twilio.com/v1/Documents"

  echo ""
  bold "Document upload preview:"
  printf "  POST %s\n" "$url"
  printf "  document_type=utility_bill\n"
  printf "  friendly_name=%s\n" "$friendly_name"
  printf "  File=@%s\n" "$pdf_path"

  confirm_yn "Upload document now?" "y" || { warn "Cancelled."; return 1; }

  # API call => start logging now
  start_logging_if_needed

  local resp
  resp="$(curl --silent --show-error --location \
    -X POST "$url" \
    -u "${AUTH_USER}:${AUTH_PASS}" \
    -F "friendly_name=${friendly_name}" \
    -F "File=@${pdf_path}" \
    -F "document_type=utility_bill")"

  echo ""
  bold "Upload response:"
  pretty_print_json "$resp"

  local sid mime
  sid="$(json_get "$resp" "sid")"
  mime="$(json_get "$resp" "mime_type")"

  [[ -n "$sid" ]] || { err "No 'sid' returned; upload likely failed."; return 1; }
  [[ -n "$mime" ]] || warn "mime_type is empty — per docs, this can indicate the upload had no content or failed."

  ok "Document uploaded. DocumentSid: $sid"
  printf "%s" "$sid"
}

compute_end_time_from_start_and_hours() {
  local start="$1"
  local hours="$2"

  python3 -c '
from datetime import datetime, timedelta
import re, sys
start=sys.argv[1]
hours=int(sys.argv[2])
m=re.match(r"^(\d{2}:\d{2}:\d{2})([+-]\d{2}:\d{2})$", start)
if not m:
  print("")
  sys.exit(1)
t,offset=m.groups()
dt=datetime.fromisoformat("2000-01-01T"+t+offset)
dt2=dt+timedelta(hours=hours)
print(dt2.strftime("%H:%M:%S")+offset)
' "$start" "$hours"
}

op_submit_port_in_request() {
  bold "Submit Port-In Request (single US non-toll-free number)"
  warn "This script is set up for ONE number per port-in request."

  get_auth

  local account_sid=""
  read -r -p "Enter your Twilio Account SID (used in request body): " account_sid
  confirm_value "Account SID" "$account_sid" || { warn "Cancelled."; return; }

  local raw_phone=""
  read -r -p "Enter US phone number to port (any format): " raw_phone

  local ten
  ten="$(normalize_us_10_digits "$raw_phone")" || { err "Invalid phone number. Need 10 digits (or 11 starting with 1)."; return; }

  local e164
  e164="$(format_e164_us "$ten")"
  confirm_value "Normalized phone number (E.164)" "$e164" || { warn "Cancelled."; return; }

  local pdf_path=""
  prompt_path "Enter path to utility bill PDF: " "$(pwd)" pdf_path
  confirm_value "Utility bill PDF path" "$pdf_path" || { warn "Cancelled."; return; }

  local friendly_name="phone${ten:6:4}-utility-bill-$(date +%Y-%m)"
  local tmp=""
  read -r -p "Enter friendly_name for document [default: ${friendly_name}]: " tmp
  friendly_name="${tmp:-$friendly_name}"
  confirm_value "Document friendly_name" "$friendly_name" || { warn "Cancelled."; return; }

  local notification_csv
  notification_csv="$(collect_notification_emails)"
  local notification_json
  notification_json="$(emails_csv_to_json_array "$notification_csv")"

  # Upload document (starts logging because it's an API call)
  local document_sid
  document_sid="$(upload_document_utility_bill "$pdf_path" "$friendly_name")" || return

  local pin=""
  read -r -p "Enter losing-carrier PIN (press Enter if not required): " pin
  if [[ -z "$pin" ]]; then
    confirm_yn "No PIN provided. Confirm losing carrier does NOT require a PIN for port-out?" "n" || {
      warn "Cancelled — enter the PIN and try again."
      return
    }
  else
    confirm_value "PIN" "$pin" || { warn "Cancelled."; return; }
  fi

  local default_name="shaun chokshi"
  local customer_name="$default_name"
  read -r -p "Enter customerName (losing carrier) [default: ${default_name}]: " tmp
  customer_name="${tmp:-$default_name}"
  confirm_value "customerName" "$customer_name" || return

  local auth_rep="$customer_name"
  read -r -p "Enter authorizedRepresentative [default: same as customerName]: " tmp
  auth_rep="${tmp:-$customer_name}"
  confirm_value "authorizedRepresentative" "$auth_rep" || return

  local auth_email=""
  read -r -p "Enter authorizedRepresentativeEmail (LOA signer email): " auth_email
  confirm_value "authorizedRepresentativeEmail" "$auth_email" || return

  local target_date=""
  read -r -p "Enter target port-in date (YYYY-MM-DD): " target_date
  confirm_value "target_port_in_date" "$target_date" || return

  local start_time=""
  read -r -p "Enter target port-in time start (HH:MM:SS-05:00 e.g. 10:15:00-05:00): " start_time
  confirm_value "target_port_in_time_range_start" "$start_time" || return

  local duration_hours="24"
  read -r -p "Enter time range duration hours [default: 24]: " tmp
  duration_hours="${tmp:-24}"
  confirm_value "Duration (hours)" "$duration_hours" || return

  local end_time=""
  end_time="$(compute_end_time_from_start_and_hours "$start_time" "$duration_hours")" || true
  [[ -n "$end_time" ]] || { err "Could not compute end time. Ensure start time is like HH:MM:SS-05:00"; return; }
  confirm_value "target_port_in_time_range_end (computed)" "$end_time" || return

  echo ""
  bold "Losing carrier service address (as on bill / account)"
  local street city state zip country
  read -r -p "Street: " street
  confirm_value "Street" "$street" || return
  read -r -p "City: " city
  confirm_value "City" "$city" || return
  read -r -p "State (2 letters): " state
  confirm_value "State" "$state" || return
  read -r -p "ZIP: " zip
  confirm_value "ZIP" "$zip" || return
  country="US"
  confirm_value "Country" "$country" || return

  local account_number=""
  read -r -p "Losing carrier account number: " account_number
  confirm_value "account_number" "$account_number" || return

  local atn="$e164"
  read -r -p "Account telephone number (ATN) [default: ${e164}]: " tmp
  atn="${tmp:-$e164}"
  confirm_value "account_telephone_number" "$atn" || return

  local customer_type="Business"
  read -r -p "Customer type [Business/Residential] (default: Business): " tmp
  customer_type="${tmp:-Business}"
  confirm_value "customer_type" "$customer_type" || return

  # Build JSON payload (no heredoc; safer)
  local payload
  payload="$(python3 -c '
import json,sys
account_sid=sys.argv[1]
target_date=sys.argv[2]
start_time=sys.argv[3]
end_time=sys.argv[4]
doc_sid=sys.argv[5]
phone=sys.argv[6]
pin=sys.argv[7]
customer_type=sys.argv[8]
customer_name=sys.argv[9]
acct_num=sys.argv[10]
atn=sys.argv[11]
auth_rep=sys.argv[12]
auth_email=sys.argv[13]
street=sys.argv[14]
city=sys.argv[15]
state=sys.argv[16]
zipc=sys.argv[17]
country=sys.argv[18]
notification_emails=json.loads(sys.argv[19])

phone_entry={"phone_number": phone}
if pin.strip():
  phone_entry["pin"]=pin.strip()

obj={
  "account_sid": account_sid,
  "target_port_in_date": target_date,
  "target_port_in_time_range_start": start_time,
  "target_port_in_time_range_end": end_time,
  "notification_emails": notification_emails,
  "losing_carrier_information": {
    "customer_type": customer_type,
    "customer_name": customer_name,
    "account_number": acct_num,
    "account_telephone_number": atn,
    "authorized_representative": auth_rep,
    "authorized_representative_email": auth_email,
    "address_sid": None,
    "address": {
      "street": street,
      "street_2": None,
      "city": city,
      "state": state,
      "zip": zipc,
      "country": country
    }
  },
  "phone_numbers": [phone_entry],
  "documents": [doc_sid]
}
print(json.dumps(obj, indent=2))
' \
"$account_sid" "$target_date" "$start_time" "$end_time" "$document_sid" "$e164" "$pin" \
"$customer_type" "$customer_name" "$account_number" "$atn" "$auth_rep" "$auth_email" \
"$street" "$city" "$state" "$zip" "$country" "$notification_json")"

  echo ""
  bold "Port-In Request JSON Preview:"
  printf "%s\n" "$payload"

  local url="https://numbers.twilio.com/v1/Porting/PortIn"
  echo ""
  bold "Request preview:"
  printf "  POST %s\n" "$url"

  confirm_yn "Send port-in request now?" "y" || { warn "Cancelled."; return; }

  # API call => ensure logging is on
  start_logging_if_needed

  local resp
  resp="$(curl_json "POST" "$url" "$payload")"

  echo ""
  bold "Response:"
  pretty_print_json "$resp"

  local port_in_sid
  port_in_sid="$(json_get "$resp" "sid")"
  [[ -n "$port_in_sid" ]] && ok "Port-in request created. PortInRequestSid: $port_in_sid" || warn "No 'sid' found in response; check list/status."
}

op_list_port_in_requests() {
  bold "List Port-In Requests"
  warn "Configured to use Account SID + Auth Token (global token), per your note."
  get_auth

  local size="20"
  local tmp=""
  read -r -p "Page size (default 20): " tmp
  size="${tmp:-20}"
  confirm_value "Size" "$size" || return

  local url="https://numbers.twilio.com/v1/Porting/PortIn/PortInRequests?Size=${size}"
  echo ""
  bold "Request preview:"
  printf "  GET %s\n" "$url"

  confirm_yn "Send request now?" "y" || { warn "Cancelled."; return; }
  start_logging_if_needed

  local resp
  resp="$(curl_json "GET" "$url")"

  echo ""
  bold "Response:"
  pretty_print_json "$resp"
}

op_check_port_in_status() {
  bold "Check Port-In Request Status (by SID via list filter)"
  get_auth

  local sid=""
  read -r -p "Enter PortInRequestSid (e.g., KWxxxxxxxx...): " sid
  confirm_value "PortInRequestSid" "$sid" || return

  local url="https://numbers.twilio.com/v1/Porting/PortIn/PortInRequests?PortInRequestSid=${sid}&Size=20"
  echo ""
  bold "Request preview:"
  printf "  GET %s\n" "$url"

  confirm_yn "Send request now?" "y" || { warn "Cancelled."; return; }
  start_logging_if_needed

  local resp
  resp="$(curl_json "GET" "$url")"

  echo ""
  bold "Response:"
  pretty_print_json "$resp"
}

# ---------------------- Main menu ---------------------------------------------

main_menu() {
  while true; do
    echo ""
    bold "Twilio Porting CLI"
    echo "1) Check a number for portability"
    echo "2) Submit a port-in request (1 number)"
    echo "3) Check port-in request status (by SID)"
    echo "4) List port-in requests"
    echo "5) Exit"
    echo ""

    local choice=""
    read -r -p "Select operation [1-5]: " choice

    case "$choice" in
      1) op_portability_check ;;
      2) op_submit_port_in_request ;;
      3) op_check_port_in_status ;;
      4) op_list_port_in_requests ;;
      5) ok "Bye."; exit 0 ;;
      *) warn "Please choose 1-5." ;;
    esac
  done
}

main_menu
