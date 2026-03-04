#!/bin/bash

# SSL Certificate Validity Checker and Post-Renewal Action Script

set -euo pipefail

# Path to the SSL certificate to monitor
CERT_PATH="/etc/letsencrypt/live/gitlab.bbgaero.tech/fullchain.pem"
LIVEDIR="/etc/letsencrypt/live/gitlab.bbgaero.tech"
PRIVKEY="privkey.pem"
CERT="fullchain.pem"
OUTDIR="/usr/local/certs"
ZABBIXOUT="${OUTDIR}/zabbix"
WEBDIR="/etc/letsencrypt/live/monitor.bbgaero.tech"
WEBOUT="${ZABBIXOUT}/www-data"

# Grace period (in minutes) after Not Before date to trigger the command
GRACE_PERIOD_MINUTES=80

# ============================================================================
# POST-RENEWAL COMMAND FUNCTION - EDIT THIS FUNCTION
# ============================================================================
execute_post_renewal_command() {
    cp ${LIVEDIR}/${PRIVKEY} ${ZABBIXOUT}/${PRIVKEY}
    cp ${LIVEDIR}/${CERT} ${ZABBIXOUT}/${CERT}
    chown zabbix ${ZABBIXOUT}/*.pem
    systemctl restart zabbix-server.service
    cp ${WEBDIR}/${PRIVKEY} ${WEBOUT}/${PRIVKEY}
    cp ${WEBDIR}/${CERT} ${WEBOUT}/${CERT}
    chown www-data ${WEBOUT}/*.pem
    systemctl restart zabbix-agent2.service
    systemctl reload apache2.service
    systemctl restart apache2.service
}

# ============================================================================
# END CONFIGURATION
# ============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to log messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date -u +"%Y-%m-%dT%H:%M:%SZ") - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date -u +"%Y-%m-%dT%H:%M:%SZ") - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date -u +"%Y-%m-%dT%H:%M:%SZ") - $1"
}

# Validate configuration
if [[ "$CERT_PATH" == "/path/to/fullchain.pem" ]]; then
    log_error "CERT_PATH not configured - edit the script and set the correct certificate path"
    exit 1
fi

if [[ ! -f "$CERT_PATH" ]]; then
    log_error "Certificate file not found: $CERT_PATH"
    exit 1
fi

# Extract certificate directory and filename
CERT_DIR=$(dirname "$CERT_PATH")
CERT_FILENAME=$(basename "$CERT_PATH")

log_info "Checking certificate: $CERT_PATH"

# Extract Not Before and Not After dates
CERT_DATES=$(openssl x509 -noout -dates -in "$CERT_PATH" 2>/dev/null)

if [[ -z "$CERT_DATES" ]]; then
    log_error "Failed to read certificate dates"
    exit 1
fi

NOT_BEFORE=$(echo "$CERT_DATES" | grep "notBefore=" | cut -d= -f2)
NOT_AFTER=$(echo "$CERT_DATES" | grep "notAfter=" | cut -d= -f2)

log_info "Not Before: $NOT_BEFORE"
log_info "Not After:  $NOT_AFTER"

# Convert dates to epoch time (seconds since 1970-01-01)
NOT_BEFORE_EPOCH=$(date -d "$NOT_BEFORE" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$NOT_BEFORE" +%s 2>/dev/null)
NOT_AFTER_EPOCH=$(date -d "$NOT_AFTER" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$NOT_AFTER" +%s 2>/dev/null)
CURRENT_EPOCH=$(date +%s)

# Check if certificate is currently valid
if [[ $CURRENT_EPOCH -lt $NOT_BEFORE_EPOCH ]]; then
    log_warn "Certificate is not yet valid (Not Before date has not been reached)"
    exit 0
fi

if [[ $CURRENT_EPOCH -gt $NOT_AFTER_EPOCH ]]; then
    log_error "Certificate has expired (Not After date has been exceeded)"
    exit 1
fi

log_info "Certificate is currently valid"

# Calculate time since Not Before date (in minutes)
TIME_SINCE_NOT_BEFORE=$(( (CURRENT_EPOCH - NOT_BEFORE_EPOCH) / 60 ))
log_info "Time since Not Before: $TIME_SINCE_NOT_BEFORE minutes"

# Check if Not Before is within the grace period
if [[ $TIME_SINCE_NOT_BEFORE -gt $GRACE_PERIOD_MINUTES ]]; then
    log_info "Not Before date is older than $GRACE_PERIOD_MINUTES minutes. No action needed."
    exit 0
fi

log_info "Certificate was renewed within the past $GRACE_PERIOD_MINUTES minutes"

# Check for backup files with the expected patterns
# Patterns: fullchain.pem.backup_YYYY-MM-DDTHH-MM-SSZ or privkey.pem.backup_YYYY-MM-DDTHH-MM-SSZ
BACKUP_PATTERN1="${CERT}.backup_[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]-[0-9][0-9]-[0-9][0-9]Z"
BACKUP_PATTERN2="${PRIVKEY}.backup_[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]-[0-9][0-9]-[0-9][0-9]Z"

BACKUP_FILES=$(find "$OUTDIR" -maxdepth 1 \( -name "$BACKUP_PATTERN1" -o -name "$BACKUP_PATTERN2" \) 2>/dev/null | sort -r)

if [[ -z "$BACKUP_FILES" ]]; then
    log_warn "No backup files found matching expected patterns"
else
    log_info "Found backup files:"
    echo "$BACKUP_FILES" | while read -r backup_file; do
        echo "  - $(basename "$backup_file")"
    done
fi

# Execute post-renewal command
log_info "Executing post-renewal command..."

if execute_post_renewal_command; then
    log_info "Post-renewal actions completed successfully"
else
    log_error "Post-renewal command failed"
    exit 1
fi

exit 0
