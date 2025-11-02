#!/usr/bin/env bash
# ugrep-replace.sh
# Mass find/replace with ugrep preview + per-file backups

set -euo pipefail

echo "Search mode:"
select MODE in "plain (fixed string search)" "regex (PCRE, like ugrep -P)"; do
  case $REPLY in
    1) SEARCH_MODE="plain"; break;;
    2) SEARCH_MODE="regex"; break;;
    *) echo "Please choose 1 or 2.";;
  esac
done

read -r -p "Enter the search pattern (what to find): " PATTERN
read -r -p "Enter the replacement text (plain text): " REPLACEMENT
#read -r -p "Enter the path to search/replace in: " SEARCH_PATH
SEARCH_PATH="$(pwd)"
read -e -i "$SEARCH_PATH" -p "Enter path to search/replace in:" SEARCH_PATH


UGREP_BASE=(ugrep --color=auto -RnwHos -I)

if [[ "$SEARCH_MODE" == "plain" ]]; then
  UGREP_FIND=( "${UGREP_BASE[@]}" -F -e "$PATTERN" -- "$SEARCH_PATH" )
  UGREP_LIST_FILES=( ugrep -RIl -F -I -e "$PATTERN" -- "$SEARCH_PATH" )
else
  UGREP_FIND=( "${UGREP_BASE[@]}" -P -e "$PATTERN" -- "$SEARCH_PATH" )
  UGREP_LIST_FILES=( ugrep -RIl -P -I -e "$PATTERN" -- "$SEARCH_PATH" )
fi

echo
echo "=== Preview matches (no changes yet) ==="
"${UGREP_FIND[@]}" || true

echo
read -r -p "Proceed with replacement and per-file backups? [y/N] " OK
if [[ ! "$OK" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

echo
echo "Backing up and replacing..."

# Read the list of files (one per line)
mapfile -t FILES < <("${UGREP_LIST_FILES[@]}" || true)

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No files contained the target pattern. Nothing to do."
  exit 0
else

#CHANGED_COUNT=0

for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue

  dir=$(dirname -- "$f")
  base=$(basename -- "$f")
  backup="$dir/.original-$base"

  cp -p -- "$f" "$backup" 2>/dev/null || cp -- "$f" "$backup"

  if [[ "$SEARCH_MODE" == "plain" ]]; then
    # Literal search & literal replace, safe for slashes and metacharacters.
    UGREP_REPL_PAT="$PATTERN" UGREP_REPL_REP="$REPLACEMENT" \
      perl -0777 -i -pe 'BEGIN{$p=$ENV{UGREP_REPL_PAT}; $r=$ENV{UGREP_REPL_REP}}
                          s{\Q$p\E}{\Q$r\E}g' -- "$f"
  else
    # Regex search (Perl-compatible), literal replacement.
    UGREP_REPL_PAT="$PATTERN" UGREP_REPL_REP="$REPLACEMENT" \
      perl -0777 -i -pe 'BEGIN{$p=$ENV{UGREP_REPL_PAT}; $r=$ENV{UGREP_REPL_REP}}
                          s{$p}{\Q$r\E}g' -- "$f"

  echo "$f  (backup: $(dirname -- "$f")/.original-$(basename -- "$f"))"

  fi

 # (( CHANGED_COUNT++ ))
#echo "Completed replacements in $CHANGED_COUNT file(s)."

done

echo

fi

echo "=== Files changed (backups created alongside originals) ==="

echo
echo "=== Post-change verification: occurrences of the NEW string ==="
ugrep --color=auto -RnwHos -F -I -e "$REPLACEMENT" -- "$SEARCH_PATH" || true

echo
echo "Done."
