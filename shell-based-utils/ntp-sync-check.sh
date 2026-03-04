#!/usr/bin/env bash
set -euo pipefail

main() {
  local NTPG=1
  local NTPB=0

  # 1 = require current server in allowlist; 0 = ignore allowlist
  local REQUIRE_ALLOWLIST=1

  local -a NtpServerList=("129.6.15.27" "129.6.15.28" "129.6.15.29" "129.6.15.30")

  local ntp_synced ntp_enabled
  ntp_enabled="$(timedatectl show -p NTP --value 2>/dev/null || true)"
  ntp_synced="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)"

  if [[ "$ntp_synced" != "yes" ]]; then
    echo "Data:"
    echo "NtpOutput $NTPB"
    return 0
  fi

  # If NTP is explicitly disabled, fail.
  if [[ -n "$ntp_enabled" && "$ntp_enabled" != "yes" ]]; then
    echo "Data:"
    echo "NtpOutput $NTPB"
    return 0
  fi

  # Detect chrony vs timesyncd
  local svc="unknown"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active --quiet chronyd && svc="chronyd" || true
    [[ "$svc" == "unknown" ]] && systemctl is-active --quiet systemd-timesyncd && svc="systemd-timesyncd" || true
  fi

  # Determine current server (best effort)
  local current_server=""
  if [[ "$svc" == "chronyd" ]] && command -v chronyc >/dev/null 2>&1; then
    # Selected source marked with ^*
    current_server="$(chronyc -n sources 2>/dev/null | awk '$1 ~ /\^\*/ {print $2; exit}' || true)"
  elif [[ "$svc" == "systemd-timesyncd" ]]; then
    current_server="$(timedatectl show -p ServerName --value 2>/dev/null || true)"
    if [[ -z "$current_server" ]]; then
      current_server="$(timedatectl status 2>/dev/null | awk -F': *' '/Server:/{print $2; exit}' || true)"
    fi
  fi

  if [[ "$REQUIRE_ALLOWLIST" -eq 1 ]]; then
    # If we can't determine the server, fail (strict mode).
    if [[ -z "$current_server" ]]; then
      echo "Data:"
      echo "NtpOutput $NTPB"
      return 0
    fi

    local ok=0
    for ip in "${NtpServerList[@]}"; do
      [[ "$current_server" == "$ip" ]] && ok=1 && break
    done

    echo "Data:"
    [[ $ok -eq 1 ]] && echo "NtpOutput $NTPG" || echo "NtpOutput $NTPB"
  else
    # Synced is enough
    echo "Data:"
    echo "NtpOutput $NTPG"
  fi
}

main "$@"
