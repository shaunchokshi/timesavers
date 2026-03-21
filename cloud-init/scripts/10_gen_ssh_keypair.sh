#!/usr/bin/env bash
set -euo pipefail

BOLD="\e[1m"; GREEN="\e[32m"; RED="\e[31m"; YELLOW="\e[33m"; RESET="\e[0m"

WORKDIR_DEFAULT="${HOME}/devspace/myprojects/portable-configs/cloud-init"
read -e -i "$WORKDIR_DEFAULT" -p "Enter cloud-init workspace root: " WORKDIR

TGT_SSH_TAG_DEFAULT="CHANGEME"
read -e -i "${TGT_SSH_TAG_DEFAULT}" -p "Enter SSH_TAG label for the target host: " TGT_SSH_TAG

TGT_WORKDIR="${WORKDIR}/${TGT_SSH_TAG}"
TGT_ENV="${TGT_WORKDIR}/.env.${TGT_SSH_TAG}"

USER_SECRETS_PATH_DEFAULT="${HOME}/.secrets"
read -e -i "$USER_SECRETS_PATH_DEFAULT" -p "Enter secrets dir to store private keys: " USER_SECRETS_PATH
mkdir -p "${USER_SECRETS_PATH}"
mkdir -p "${TGT_WORKDIR}"

if [ ! -f "${TGT_ENV}" ]; then
  echo -e "${RED}Missing ${TGT_ENV}. Run 00_init_host.sh first.${RESET}"
  exit 1
fi

DTG="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
KEY_BASENAME="${TGT_SSH_TAG}.${DTG}"
KEY_TMP="${TGT_WORKDIR}/${KEY_BASENAME}"
KEY_DST="${USER_SECRETS_PATH}/${KEY_BASENAME}.key"

REALRUN_LOGFILE="${TGT_WORKDIR}/${KEY_BASENAME}.log"

echo -e "${BOLD}Generating ed25519 key:${RESET} ${KEY_BASENAME}" | tee -a "${REALRUN_LOGFILE}"
ssh-keygen -q -t ed25519 -C "${TGT_SSH_TAG}.${DTG}" -N "" -f "${KEY_TMP}" |& tee -a "${REALRUN_LOGFILE}"

mv -f "${KEY_TMP}" "${KEY_DST}"
chmod 600 "${KEY_DST}"
echo -e "${GREEN}Private key stored:${RESET} ${KEY_DST}" | tee -a "${REALRUN_LOGFILE}"

PUBKEY_CONTENT="$(cat "${KEY_TMP}.pub")"
rm -f "${KEY_TMP}.pub"

# Append into env file (you can later decide whether this key is for root or user)
# Default: user key placeholder
echo "" >> "${TGT_ENV}"
echo "# Added by 10_gen_ssh_keypair.sh at ${DTG}" >> "${TGT_ENV}"
echo "USER_SSH_PUBKEY_1='${PUBKEY_CONTENT}'" >> "${TGT_ENV}"

echo -e "${GREEN}Appended USER_SSH_PUBKEY_1 to:${RESET} ${TGT_ENV}" | tee -a "${REALRUN_LOGFILE}"
