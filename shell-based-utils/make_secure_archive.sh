#!/bin/bash
set -euo pipefail

# Simple colors for messages (optional)
BOLD="\e[1m"
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
RESET="\e[0m"

echo -e "${BOLD}Secure AES-256 ZIP archive creator${RESET}"

# 1. Check for 7z
if ! command -v 7z >/dev/null 2>&1; then
    echo -e "${RED}Error:${RESET} '7z' (p7zip) is not installed."
    echo "On Arch/CachyOS, you can install it with:"
    echo "  sudo pacman -S p7zip"
    exit 1
fi

# 2. Ask for source path (directory or single file)
SOURCE_PATH="$(pwd)"
read -e -i "$SOURCE_PATH" -p "Enter path to archive (file or directory): " SOURCE_PATH
SOURCE_PATH="${SOURCE_PATH%/}"  # strip trailing slash if any

if [ ! -e "$SOURCE_PATH" ]; then
    echo -e "${RED}Error:${RESET} Path does not exist: $SOURCE_PATH"
    exit 1
fi

# 3. Build default archive name respecting your conventions
BASENAME="$(basename "$SOURCE_PATH")"
TIMESTAMP="$(date +%Y-%m-%dT%H%M%S)"   # ISO-ish, but filename-safe (no colons)
DEFAULT_ARCHIVE_NAME="secure_archive-${BASENAME}_${TIMESTAMP}.zip"

read -e -i "$DEFAULT_ARCHIVE_NAME" -p "Enter output archive filename: " ARCHIVE_NAME

# Enforce your no-space rule: replace spaces with underscores
ARCHIVE_NAME="${ARCHIVE_NAME// /_}"

# Ensure it ends with .zip
if [[ "$ARCHIVE_NAME" != *.zip ]]; then
    ARCHIVE_NAME="${ARCHIVE_NAME}.zip"
fi

# 4. Prompt for password (hidden input + confirmation)
while true; do
    read -s -p "Enter archive password: " ARCHIVE_PWD
    echo
    read -s -p "Confirm archive password: " ARCHIVE_PWD_CONFIRM
    echo
    if [[ "$ARCHIVE_PWD" != "$ARCHIVE_PWD_CONFIRM" ]]; then
        echo -e "${YELLOW}Passwords do not match. Please try again.${RESET}"
    elif [[ -z "$ARCHIVE_PWD" ]]; then
        echo -e "${YELLOW}Password cannot be empty. Please try again.${RESET}"
    else
        break
    fi
done

# 5. Create the AES-256 encrypted ZIP with 7z
echo -e "${GREEN}Creating AES-256 encrypted ZIP archive...${RESET}"
echo "Source : $SOURCE_PATH"
echo "Output : $ARCHIVE_NAME"

# -tzip  : create a ZIP archive
# -mem=AES256 : use AES-256 encryption
# -p...  : set password
# "--"   : end of options (in case paths start with '-')
7z a -tzip -mem=AES256 -p"$ARCHIVE_PWD" -- "$ARCHIVE_NAME" "$SOURCE_PATH"

echo -e "${GREEN}Done.${RESET}"
echo "Encrypted archive created: ${BOLD}${ARCHIVE_NAME}${RESET}"
echo
echo "Recipients can usually open it by double-clicking (macOS, most Linux,"
echo "and Windows with built-in tools or 7-Zip), then entering the password."
