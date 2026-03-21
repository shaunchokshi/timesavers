#!/usr/bin/env bash
set -euo pipefail

GITIGNORE="${HOME}/.gitignore"
touch "${GITIGNORE}"

ensure_line() {
  local line="$1"
  grep -qxF "$line" "${GITIGNORE}" || echo "$line" >> "${GITIGNORE}"
}

# Global ignores
ensure_line "*.key"
ensure_line ".env"
ensure_line ".env.*"

echo "Updated ${GITIGNORE} with global ignores."

# Optional: remind about git excludesfile (doesn't forcibly change your config)
echo ""
echo "To ensure Git uses it globally:"
echo '  git config --global core.excludesfile "${HOME}/.gitignore"'
