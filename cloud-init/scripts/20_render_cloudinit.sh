#!/usr/bin/env bash
set -euo pipefail

WORKDIR_DEFAULT="${HOME}/devspace/myprojects/portable-configs/cloud-init"
read -e -i "$WORKDIR_DEFAULT" -p "Enter cloud-init workspace root: " WORKDIR

TEMPLATES_DEFAULT="${HOME}/devspace/myprojects/timesavers/cloud-init/templates"
read -e -i "$TEMPLATES_DEFAULT" -p "Enter templates path: " TEMPLATES

TGT_SSH_TAG_DEFAULT="CHANGEME"
read -e -i "${TGT_SSH_TAG_DEFAULT}" -p "Enter SSH_TAG label for the target host: " TGT_SSH_TAG

TGT_WORKDIR="${WORKDIR}/${TGT_SSH_TAG}"
TGT_ENV="${TGT_WORKDIR}/.env.${TGT_SSH_TAG}"
HOSTMETA="${TGT_WORKDIR}/hostmeta.${TGT_SSH_TAG}.txt"

MASTER_TEMPLATE="${TEMPLATES}/cloud-init_master.yaml"
OUTFILE="${TGT_WORKDIR}/cloudinit.${TGT_SSH_TAG}.yaml"

if [ ! -f "${TGT_ENV}" ]; then
  echo "Missing ${TGT_ENV}. Run 00_init_host.sh first."
  exit 1
fi
if [ ! -f "${MASTER_TEMPLATE}" ]; then
  echo "Missing ${MASTER_TEMPLATE}."
  exit 1
fi
if [ ! -f "${HOSTMETA}" ]; then
  echo "Warning: ${HOSTMETA} not found; metadata header will be minimal."
fi

set -a
# shellcheck disable=SC1090
source "${TGT_ENV}"

# Ensure SSH_TAG is present in environment (used in some placeholders)
export SSH_TAG="${SSH_TAG:-${TGT_SSH_TAG}}"

python3 - "$MASTER_TEMPLATE" "$OUTFILE" "$HOSTMETA" "$TEMPLATES" <<'PY'
import os, re, sys, pathlib

src = sys.argv[1]
dst = sys.argv[2]
meta_path = sys.argv[3] if len(sys.argv) > 3 else ""

with open(src, "r", encoding="utf-8") as f:
    data = f.read()
templates_dir = sys.argv[4] if len(sys.argv) > 4 else ""

pattern = re.compile(r"<<\$\{([A-Za-z_][A-Za-z0-9_]*)(?::([A-Za-z_][A-Za-z0-9_]*))?\}>>")

missing = set()
optional = {
    "ROOT_SSH_PUBKEY_2",
    "USER_SSH_PUBKEY_2",
    "ROOT_BASHRC_CONTENT",
    "USER_BASHRC_CONTENT",
    # StorBox fields are optional in general; if USE_STORBOX=true you can enforce them separately
    "STORBOX_MAIN",
    "STORBOX_SUBACCT",
    "STORBOX_SUBACCT_PASSWORD",
    "STORBOX_SUBURI",
}

from pathlib import Path

def read_template_file(path_value: str) -> str:
    if not templates_dir:
        raise RuntimeError("templates_dir not provided to renderer")
    p = Path(templates_dir) / path_value
    if not p.is_file():
        raise RuntimeError(f"Missing template include file: {p}")
    # Read verbatim; cloud-init YAML block will preserve newlines
    return p.read_text(encoding="utf-8")

def repl(m):
    key = m.group(1)
    path_key = m.group(2)

    # File-include placeholder: <<${LABEL:ENVVAR}>> means:
    # look up ENVVAR to get filename, then read that file from templates_dir
    if path_key:
        path_value = os.environ.get(path_key, "").strip()
        if not path_value:
            # treat missing path as empty include (or make it mandatory if you prefer)
            return ""
        return read_template_file(path_value)

    # Normal env substitution: <<${VAR}>>
    val = os.environ.get(key)
    if val is None:
        if key in optional:
            return ""
        missing.add(key)
        return m.group(0)
    return val


rendered = pattern.sub(repl, data)

# Handle USE_STORBOX flag by dropping storbox blocks entirely when disabled
use_storbox = os.environ.get("USE_STORBOX", "").strip().lower() in ("1", "true", "yes", "y")

def strip_block(text: str, start_marker: str, end_marker: str) -> str:
    lines = text.splitlines(keepends=True)
    out = []
    skipping = False
    for line in lines:
        if not skipping and start_marker in line:
            skipping = True
            continue
        if skipping and end_marker in line:
            skipping = False
            continue
        if not skipping:
            out.append(line)
    return "".join(out)

if not use_storbox:
    rendered = strip_block(rendered, "# BEGIN_STORBOX", "# END_STORBOX")
    rendered = strip_block(rendered, "# BEGIN_STORBOX_FSTAB", "# END_STORBOX_FSTAB")

# After optional stripping, re-check for unresolved STORBOX placeholders,
# but don't treat their absence as a hard error if blocks were removed.
# (The main placeholder-missing check already ran before stripping.)

if missing:
    # Remove any STORBOX-related placeholders if storbox is disabled and they
    # only existed inside the stripped blocks
    if not use_storbox:
        still_missing = {m for m in missing if not m.startswith("STORBOX_")}
    else:
        still_missing = missing
    if still_missing:
        print("ERROR: Missing required env vars:", ", ".join(sorted(still_missing)), file=sys.stderr)
        sys.exit(2)

# Inject metadata header right after #cloud-config
meta = {}
if meta_path and pathlib.Path(meta_path).is_file():
    with open(meta_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or "=" not in line:
                continue
            k, v = line.split("=", 1)
            meta[k.strip()] = v.strip()

lines = rendered.splitlines(keepends=True)
if lines and lines[0].lstrip().startswith("#cloud-config"):
    header = [lines[0]]
    # Build metadata block using whatever we have
    meta_lines = [
        "#",
        "# Render metadata:",
        f"#   SSH_TAG: {meta.get('SSH_TAG', os.environ.get('SSH_TAG', ''))}",
        f"#   HOSTNAME: {meta.get('HOSTNAME', os.environ.get('HOSTNAME', ''))}",
        f"#   DTG_UTC: {meta.get('DTG_UTC', '')}",
        f"#   VPS_PROVIDER: {meta.get('VPS_PROVIDER', '')}",
        f"#   DC_LOCATION: {meta.get('DC_LOCATION', '')}",
        f"#   MAIN_USE: {meta.get('MAIN_USE', '')}",
        f"#   PROVIDER_ADMIN: {meta.get('PROVIDER_ADMIN', '')}",
        f"#   PROJECT_PATH: {meta.get('PROJECT_PATH', '')}",
        f"#   COSTING: {meta.get('COSTING', '')}",
        f"#   DEPL_MODE: {meta.get('DEPL_MODE', '')}",
        f"#   NOTES: {meta.get('NOTES', '')}",
        "#",
    ]
    header.extend([l + "\n" for l in meta_lines])
    rest = lines[1:]
    final = header + rest
else:
    # In weird cases, just prepend the header (but keep first line as-is)
    meta_lines = [
        "# Render metadata (no #cloud-config header detected at line 1)",
        f"#   SSH_TAG: {os.environ.get('SSH_TAG', '')}",
    ]
    final = [l + "\n" for l in meta_lines] + lines

with open(dst, "w", encoding="utf-8") as f:
    f.writelines(final)

print(f"Wrote: {dst}")
PY
