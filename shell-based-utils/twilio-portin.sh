#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Twilio Porting CLI (Public Beta APIs)
# Requirements: bash, curl, python3
# Optional: jq
###############################################################################

# --------------------------- UI helpers --------------------------------------

bold() { printf "\033[1m%s\033[0m\n" "$*" >&2; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*" >&2; }
err()  { printf "\033[1;31m[!]\033[0m %s\n" "$*" >&2; }
ok()   { printf "\033[1;32m[+]\033[0m %s\n" "$*" >&2; }

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
  echo "" >&2
  bold "${label}:"
  printf "  %s\n" "$value" >&2
  confirm_yn "Confirm this is correct?" "y"
}

prompt_with_retry() {
  local prompt="$1"
  local label="$2"
  local default="${3:-}"
  local result_var="$4"
  local value=""

  while true; do
    if [[ -n "$default" ]]; then
      read -r -p "${prompt} [default: ${default}]: " value
      value="${value:-$default}"
    else
      read -r -p "${prompt}: " value
    fi

    if confirm_value "$label" "$value"; then
      printf -v "$result_var" "%s" "$value"
      return 0
    fi
  done
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

  echo "" >&2
  bold "Logging enabled"
  echo "Log file: ${LOG_FILE}" >&2
  echo "Run timestamp: $(iso_ts)" >&2
  echo "" >&2
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
  echo "" >&2
  bold "Portability reason code: ${code}"
  printf "  %s\n" "$name" >&2
  printf "  %s\n" "$desc" >&2
  echo "" >&2
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
    echo "" >&2
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
  echo "" >&2
  bold "Authentication"
  echo "Recommended: API Key + API Key Secret (scoped permissions)." >&2
  echo "Alternative: Account SID + Auth Token (global / broader permissions)." >&2
  echo "" >&2

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

  echo "" >&2
  bold "Request preview:"
  printf "  GET %s\n" "$url" >&2

  confirm_yn "Send request now?" "y" || { warn "Cancelled."; return; }

  # Only start logging when we actually attempt an API call
  start_logging_if_needed

  local resp
  resp="$(curl_json "GET" "$url")"

  echo "" >&2
  bold "Response:"
  pretty_print_json "$resp" >&2

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

op_upload_document() {
  bold "Upload Utility Bill Document"
  get_auth

  local pdf_path=""
  while true; do
    prompt_path "Enter path to utility bill PDF: " "$(pwd)" pdf_path
    confirm_value "Utility bill PDF path" "$pdf_path" && break
  done

  local default_name="utility-bill-$(date +%Y-%m)"
  local friendly_name=""
  prompt_with_retry "Enter friendly_name for document" "Document friendly_name" "$default_name" friendly_name

  local document_sid
  document_sid="$(upload_document_utility_bill "$pdf_path" "$friendly_name")" || { warn "Document upload failed."; return; }

  echo "" >&2
  ok "Document SID: $document_sid"
  bold "Save this Document SID for creating your port-in request."
  echo "" >&2
  read -n 1 -s -r -p "Press any key to return to main menu..."
}

upload_document_utility_bill() {
  local pdf_path="$1"
  local friendly_name="$2"

  [[ -f "$pdf_path" ]] || { err "File not found: $pdf_path"; return 1; }

  local url="https://numbers-upload.twilio.com/v1/Documents"

  echo "" >&2
  bold "Document upload preview:"
  printf "  POST %s\n" "$url" >&2
  printf "  document_type=utility_bill\n" >&2
  printf "  friendly_name=%s\n" "$friendly_name" >&2
  printf "  File=@%s\n" "$pdf_path" >&2

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

  echo "" >&2
  bold "Upload response:"
  pretty_print_json "$resp" >&2

  local sid mime
  sid="$(json_get "$resp" "sid")"
  mime="$(json_get "$resp" "mime_type")"

  [[ -n "$sid" ]] || { err "No 'sid' returned; upload likely failed."; return 1; }
  [[ -n "$mime" ]] || warn "mime_type is empty — per docs, this can indicate the upload had no content or failed." >&2

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

op_generate_port_in_json() {
  bold "Generate Port-In Request JSON (single US non-toll-free number)"
  warn "This script is set up for ONE number per port-in request."

  # Check if user has document SID
  echo "" >&2
  local has_doc_sid=""
  while true; do
    read -r -p "Do you have a Document SID for the utility bill already uploaded? [y/n]: " has_doc_sid
    case "${has_doc_sid,,}" in
      y|yes)
        break
        ;;
      n|no)
        echo "" >&2
        warn "Please upload the utility bill document first using CLI menu option 2."
        echo "" >&2
        read -n 1 -s -r -p "Press any key to return to main menu or press 0 to exit..."
        local key_pressed="$REPLY"
        if [[ "$key_pressed" == "0" ]]; then
          ok "Bye."; exit 0
        fi
        return
        ;;
      *)
        warn "Please answer y or n."
        ;;
    esac
  done

  get_auth

  local document_sid=""
  prompt_with_retry "Enter Document SID (e.g., RDxxxxxxxx...)" "Document SID" "" document_sid

  local account_sid=""
  prompt_with_retry "Enter your Twilio Account SID (used in request body)" "Account SID" "" account_sid

  local raw_phone=""
  local ten e164
  while true; do
    read -r -p "Enter US phone number to port (any format): " raw_phone
    ten="$(normalize_us_10_digits "$raw_phone")" || { err "Invalid phone number. Need 10 digits (or 11 starting with 1)."; continue; }
    e164="$(format_e164_us "$ten")"
    confirm_value "Normalized phone number (E.164)" "$e164" && break
  done

  local notification_csv
  notification_csv="$(collect_notification_emails)"
  local notification_json
  notification_json="$(emails_csv_to_json_array "$notification_csv")"

  local pin=""
  while true; do
    read -r -p "Enter losing-carrier PIN (press Enter if not required): " pin
    if [[ -z "$pin" ]]; then
      if confirm_yn "No PIN provided. Confirm losing carrier does NOT require a PIN for port-out?" "n"; then
        break
      fi
    else
      confirm_value "PIN" "$pin" && break
    fi
  done

  local default_name="shaun chokshi"
  local customer_name=""
  prompt_with_retry "Enter customerName (losing carrier)" "customerName" "$default_name" customer_name

  local auth_rep=""
  prompt_with_retry "Enter authorizedRepresentative" "authorizedRepresentative" "$customer_name" auth_rep

  local auth_email=""
  prompt_with_retry "Enter authorizedRepresentativeEmail (LOA signer email)" "authorizedRepresentativeEmail" "" auth_email

  local target_date=""
  prompt_with_retry "Enter target port-in date (YYYY-MM-DD)" "target_port_in_date" "" target_date

  local start_time=""
  prompt_with_retry "Enter target port-in time start (HH:MM:SS-05:00 e.g. 10:15:00-05:00)" "target_port_in_time_range_start" "" start_time

  local duration_hours=""
  prompt_with_retry "Enter time range duration hours" "Duration (hours)" "24" duration_hours

  local end_time=""
  while true; do
    end_time="$(compute_end_time_from_start_and_hours "$start_time" "$duration_hours")" || true
    if [[ -z "$end_time" ]]; then
      err "Could not compute end time. Ensure start time is like HH:MM:SS-05:00"
      prompt_with_retry "Enter target port-in time start (HH:MM:SS-05:00 e.g. 10:15:00-05:00)" "target_port_in_time_range_start" "" start_time
    else
      confirm_value "target_port_in_time_range_end (computed)" "$end_time" && break
      err "Re-enter time parameters"
      prompt_with_retry "Enter target port-in time start (HH:MM:SS-05:00 e.g. 10:15:00-05:00)" "target_port_in_time_range_start" "" start_time
      prompt_with_retry "Enter time range duration hours" "Duration (hours)" "24" duration_hours
    fi
  done

  echo "" >&2
  bold "Losing carrier service address (as on bill / account)"
  local street city state zip country
  prompt_with_retry "Street" "Street" "" street
  prompt_with_retry "City" "City" "" city
  prompt_with_retry "State (2 letters)" "State" "" state
  prompt_with_retry "ZIP" "ZIP" "" zip
  country="US"
  while true; do
    confirm_value "Country" "$country" && break
  done

  local account_number=""
  prompt_with_retry "Losing carrier account number" "account_number" "" account_number

  local atn=""
  prompt_with_retry "Account telephone number (ATN)" "account_telephone_number" "$e164" atn

  local customer_type=""
  prompt_with_retry "Customer type [Business/Residential]" "customer_type" "Business" customer_type

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

  # Generate filename with phone number and ISO 8601 timestamp
  local json_filename="port-in-request-${e164}-$(iso_ts).json"

  # Write JSON to file
  printf "%s\n" "$payload" > "$json_filename"

  echo "" >&2
  bold "Port-In Request JSON Preview:"
  printf "%s\n" "$payload" >&2

  echo "" >&2
  ok "The port-in request JSON has been generated and written to file: $json_filename"
  echo "" >&2
  bold "To submit the JSON, run this command from your terminal after exiting the main menu:"
  echo "" >&2
  printf "  curl -X POST https://numbers.twilio.com/v1/Porting/PortIn \\\\\n" >&2
  printf "    -u \"\${API_KEY}:\${API_SECRET}\" \\\\\n" >&2
  printf "    -H \"Content-Type: application/json\" \\\\\n" >&2
  printf "    --data @%s\n" "$json_filename" >&2
  echo "" >&2
  read -n 1 -s -r -p "Press any key to return to main menu or press 0 to exit this utility and return to your terminal session..."
  local key_pressed="$REPLY"
  echo "" >&2
  if [[ "$key_pressed" == "0" ]]; then
    ok "Bye."; exit 0
  fi
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
  echo "" >&2
  bold "Request preview:"
  printf "  GET %s\n" "$url" >&2

  confirm_yn "Send request now?" "y" || { warn "Cancelled."; return; }
  start_logging_if_needed

  local resp
  resp="$(curl_json "GET" "$url")"

  echo "" >&2
  bold "Response:"
  pretty_print_json "$resp" >&2
}

op_check_port_in_status() {
  bold "Check Port-In Request Status (by SID via list filter)"
  get_auth

  local sid=""
  read -r -p "Enter PortInRequestSid (e.g., KWxxxxxxxx...): " sid
  confirm_value "PortInRequestSid" "$sid" || return

  local url="https://numbers.twilio.com/v1/Porting/PortIn/PortInRequests?PortInRequestSid=${sid}&Size=20"
  echo "" >&2
  bold "Request preview:"
  printf "  GET %s\n" "$url" >&2

  confirm_yn "Send request now?" "y" || { warn "Cancelled."; return; }
  start_logging_if_needed

  local resp
  resp="$(curl_json "GET" "$url")"

  echo "" >&2
  bold "Response:"
  pretty_print_json "$resp" >&2
}

# ---------------------- Main menu ---------------------------------------------

main_menu() {
  while true; do
    echo "" >&2
    bold "Twilio Porting CLI"
    echo "1) Check a number for portability" >&2
    echo "2) Upload utility bill document" >&2
    echo "3) Generate port-in request JSON (1 number)" >&2
    echo "4) Check port-in request status (by SID)" >&2
    echo "5) List port-in requests" >&2
    echo "6) Exit" >&2
    echo "" >&2

    local choice=""
    read -r -p "Select operation [1-6]: " choice

    case "$choice" in
      1) op_portability_check ;;
      2) op_upload_document ;;
      3) op_generate_port_in_json ;;
      4) op_check_port_in_status ;;
      5) op_list_port_in_requests ;;
      6) ok "Bye."; exit 0 ;;
      *) warn "Please choose 1-6." ;;
    esac
  done
}

main_menu
