
#!/usr/bin/env bash
set -euo pipefail

SEARCH_PATH="$(pwd)"
read -e -i "$SEARCH_PATH" -p "Enter path to your cloud-init workspace root: " WORKDIR

TEMPLATES_DEFAULT="${HOME}/devspace/myprojects/timesavers/cloud-init/templates"
read -e -i "$TEMPLATES_DEFAULT" -p "Enter templates path: " TEMPLATES

DTG="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

SSH_TAG_DEFAULT="CHANGEME"
read -e -i "$SSH_TAG_DEFAULT" -p "Enter SSH_TAG label for the target host: " TGT_SSH_TAG

HOSTNAME_DEFAULT="${TGT_SSH_TAG}"
read -e -i "$HOSTNAME_DEFAULT" -p "Hostname: " TGT_HOSTNAME

read -e -i "unknown" -p "VPS/Provider (optional): " VPS_PROVIDER
read -e -i "unknown" -p "Datacenter location (optional): " DC_LOCATION
read -e -i "unknown" -p "MAIN_USE (optional): " MAIN_USE
read -e -i "unknown" -p "Provider admin account (optional): " PROVIDER_ADMIN
read -e -i "unknown" -p "Project/hierarchy identifier (recommended): " PROJECT_PATH
read -e -i "internal" -p "COSTING (internal/external/other): " COSTING
read -e -i "dev" -p "DEPL_MODE (Trial/Demo/testing/dev/Prod): " DEPL_MODE
read -e -i "" -p "Notes (optional but encouraged): " NOTES

TGT_WORKDIR="${WORKDIR}/${TGT_SSH_TAG}"
mkdir -p "${TGT_WORKDIR}"

TGT_ENV="${TGT_WORKDIR}/.env.${TGT_SSH_TAG}"
if [ ! -e "${TGT_ENV}" ]; then
  cp -v "${TEMPLATES}/env-template" "${TGT_ENV}"
  {
    echo ""
    echo "SSH_TAG=${TGT_SSH_TAG}"
    echo "HOSTNAME=${TGT_HOSTNAME}"
  } >> "${TGT_ENV}"
fi

# Append non-sensitive metadata (kept separate from secrets; you can choose to ignore or commit it)
META_FILE="${TGT_WORKDIR}/hostmeta.${TGT_SSH_TAG}.txt"
cat > "${META_FILE}" <<EOF
DTG_UTC=${DTG}
SSH_TAG=${TGT_SSH_TAG}
HOSTNAME=${TGT_HOSTNAME}
VPS_PROVIDER=${VPS_PROVIDER}
DC_LOCATION=${DC_LOCATION}
MAIN_USE=${MAIN_USE}
PROVIDER_ADMIN=${PROVIDER_ADMIN}
PROJECT_PATH=${PROJECT_PATH}
COSTING=${COSTING}
DEPL_MODE=${DEPL_MODE}
NOTES=${NOTES}
EOF

echo "Created:"
echo "  ${TGT_WORKDIR}"
echo "  ${TGT_ENV}"
echo "  ${META_FILE}"
echo ""
echo "Next: fill ${TGT_ENV}, then run 10_gen_ssh_keypair.sh and 20_render_cloudinit.sh"
