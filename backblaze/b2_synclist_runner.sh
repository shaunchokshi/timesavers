#!/usr/bin/env bash
# b2_synclist_runner.sh
# Syncs each path from ${HOME}/.secrets/.synclist.$(hostname -s) to a target rclone remote.
# Symlink-aware: can follow links, copy targets to their absolute paths, and emit a manifest.
# JSON logs suitable for SIEM ingestion.

set -euo pipefail

RETENTION_HOURS=96
TRANSFERS=8
CHECKERS=16
LOG_LEVEL="INFO"
SYMLINK_MODE="follow-and-record"   # ignore | follow-only | follow-and-record

HOST_SHORT="$(hostname -s 2>/dev/null || uname -n)"
SECRETS_DIR="${HOME}/.secrets"
SYNCLIST_FILE="${SECRETS_DIR}/.synclist.${HOST_SHORT}"

REMOTE=""       # e.g., b2crypt:host-a-backups  OR  b2raw:my-sync-island
SUBDIR_MODE="basename"  # basename | fullpath
EMIT_JSON=1

timestamp_iso(){ date -u +"%Y-%m-%dT%H:%M:%SZ"; }
json_escape(){
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
  s="${s//$'\b'/\\b}"; s="${s//$'\f'/\\f}"
  printf '%s' "$s"
}
emit_json(){ if [[ "$EMIT_JSON" -eq 1 ]]; then printf '%s\n' "$1"; fi; }

usage(){
cat <<'USAGE'
Usage: b2_synclist_runner.sh --remote <rclone_remote[:prefix]> [options]

Required:
  --remote <REMOTE>            Target rclone remote, e.g. b2crypt:host-a-backups

Options:
  --retention-hours <N>        Version retention window (default 96)
  --subdir basename|fullpath   Place each source under basename (default) or mirror full path
  --symlinks <mode>            ignore | follow-only | follow-and-record (default follow-and-record)
  --json / --no-json           Toggle JSON output (default on)
  --log-level <LEVEL>          rclone log level (default INFO)

Notes:
- Requires rclone installed and configured (b2 and (optionally) crypt).
- Uses --backup-dir .versions/<timestamp> for changed/removed files.
- Prunes .versions/ entries older than retention window.

USAGE
}

ensure_rclone(){ command -v rclone >/dev/null 2>&1 || { echo "rclone not found"; exit 1; } }

# resolve absolute real path (portable: realpath or Python)
realpath_portable(){
  if command -v realpath >/dev/null 2>&1; then
    realpath "$1" 2>/dev/null || return 1
  else
    python3 - <<'PY' "$1" || python - <<'PY' "$1"
import os, sys
p=sys.argv[1]
try:
    print(os.path.realpath(p))
except Exception:
    sys.exit(1)
PY
  fi
}

parse_args(){
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --remote) REMOTE="$2"; shift 2 ;;
      --retention-hours) RETENTION_HOURS="$2"; shift 2 ;;
      --subdir) SUBDIR_MODE="$2"; shift 2 ;;
      --symlinks) SYMLINK_MODE="$2"; shift 2 ;;
      --json) EMIT_JSON=1; shift ;;
      --no-json) EMIT_JSON=0; shift ;;
      --log-level) LOG_LEVEL="$2"; shift 2 ;;
      --help|-h) usage; exit 0 ;;
      *) echo "Unknown option: $1"; usage; exit 2 ;;
    esac
  done
  [[ -n "$REMOTE" ]] || { echo "--remote is required"; exit 2; }
  case "$SYMLINK_MODE" in ignore|follow-only|follow-and-record) : ;; *) echo "Invalid --symlinks mode"; exit 2 ;; esac
}

read_synclist(){
  if [[ ! -f "$SYNCLIST_FILE" ]]; then
    emit_json "{\"ts\":\"$(timestamp_iso)\",\"type\":\"synclist\",\"host\":\"$(json_escape "$HOST_SHORT")\",\"path\":\"$(json_escape "$SYNCLIST_FILE")\",\"exists\":false}"
    return 1
  fi
  emit_json "{\"ts\":\"$(timestamp_iso)\",\"type\":\"synclist\",\"host\":\"$(json_escape "$HOST_SHORT")\",\"path\":\"$(json_escape "$SYNCLIST_FILE")\",\"exists\":true}"
  awk 'BEGIN{RS="\n"}{line=$0; sub(/^[ \t]+/,"",line); sub(/[ \t]+$/,"",line);
       if (line ~ /^#/ || line == "") next; print line}' "$SYNCLIST_FILE"
}

# Run one rclone sync and JSON-log a summary
run_sync(){
  local src="$1" dest="$2" version_dir="$3"
  local started ended rc tmp_log transferred_bytes objects lines
  started="$(timestamp_iso)"
  tmp_log="$(mktemp -t rclone_sync_XXXX.log)"
  set +e
  rclone sync "$src" "$dest" \
    --backup-dir "$version_dir" \
    --transfers "$TRANSFERS" --checkers "$CHECKERS" \
    --fast-list \
    --b2-hard-delete=false \
    --delete-excluded \
    --exclude ".versions/**" \
    --log-file "$tmp_log" \
    --log-level "$LOG_LEVEL"
  rc=$?
  set -e
  ended="$(timestamp_iso)"
  transferred_bytes="$(grep -Eo 'Transferred: *[0-9,]+ / [0-9,]+, [0-9.]+ [A-Za-z]B' "$tmp_log" | tail -n1 || true)"
  objects="$(grep -Eo 'Checks: *[0-9,]+ \| Transferred: *[0-9,]+' "$tmp_log" | tail -n1 || true)"
  lines="$(wc -l < "$tmp_log" | tr -d ' ')"
  rm -f "$tmp_log"

  emit_json "$(printf '{\
\"ts\":\"%s\",\"type\":\"sync_item\",\"host\":\"%s\",\
\"source\":\"%s\",\"dest\":\"%s\",\"status\":\"%s\",\"exit_code\":%s,\
\"started\":\"%s\",\"ended\":\"%s\",\"log_lines\":%s,\
\"summary_bytes\":\"%s\",\"summary_objects\":\"%s\"}\n' \
"$(json_escape "$ended")" "$(json_escape "$HOST_SHORT")" \
"$(json_escape "$src")" "$(json_escape "$dest")" \
"$([[ $rc -eq 0 ]] && echo ok || echo fail)" "$rc" \
"$(json_escape "$started")" "$(json_escape "$ended")" \
"$lines" "$(json_escape "$transferred_bytes")" "$(json_escape "$objects")")"

  return "$rc"
}

main(){
  parse_args "$@"
  ensure_rclone

  local now version_dir total_ok=0 total_fail=0 any=0
  now="$(timestamp_iso)"
  version_dir="${REMOTE}/.versions/${now}"

  # We’ll accumulate a symlink manifest if needed
  local manifest_tmp; manifest_tmp="$(mktemp -t symlinks_${HOST_SHORT}_XXXX.jsonl)"
  local symlink_records=0

  while IFS= read -r SRC; do
    any=1

    # 1) Normal sync of the item, treating symlinks per SYMLINK_MODE
    if [[ ! -e "$SRC" ]]; then
      emit_json "$(printf '{\"ts\":\"%s\",\"type\":\"sync_item\",\"host\":\"%s\",\"source\":\"%s\",\"status\":\"skip\",\"reason\":\"missing\"}\n' \
        "$(json_escape "$(timestamp_iso)")" "$(json_escape "$HOST_SHORT")" "$(json_escape "$SRC")")"
      continue
    fi

    local REL=""
    case "$SUBDIR_MODE" in
      basename) REL="$(basename "$SRC")" ;;
      fullpath) REL="$(printf '%s' "$SRC" | sed 's#^/*##')" ;;
      *) REL="$(basename "$SRC")" ;;
    esac
    local DEST="${REMOTE}/${REL}"

    # Choose rclone approach for the main sync
    case "$SYMLINK_MODE" in
      ignore)
        run_sync "$SRC" "$DEST" "$version_dir" || total_fail=$((total_fail+1))
        [[ $? -eq 0 ]] && total_ok=$((total_ok+1))
        ;;
      follow-only|follow-and-record)
        # Follow links so the *symlink path* in the bucket has the file content
        # rclone flag: --copy-links follows symlinks
        local started ended rc tmp_log transferred_bytes objects lines
        started="$(timestamp_iso)"
        tmp_log="$(mktemp -t rclone_sync_XXXX.log)"
        set +e
        rclone sync "$SRC" "$DEST" \
          --copy-links \
          --backup-dir "$version_dir" \
          --transfers "$TRANSFERS" --checkers "$CHECKERS" \
          --fast-list \
          --b2-hard-delete=false \
          --delete-excluded \
          --exclude ".versions/**" \
          --log-file "$tmp_log" \
          --log-level "$LOG_LEVEL"
        rc=$?
        set -e
        ended="$(timestamp_iso)"
        transferred_bytes="$(grep -Eo 'Transferred: *[0-9,]+ / [0-9,]+, [0-9.]+ [A-Za-z]B' "$tmp_log" | tail -n1 || true)"
        objects="$(grep -Eo 'Checks: *[0-9,]+ \| Transferred: *[0-9,]+' "$tmp_log" | tail -n1 || true)"
        lines="$(wc -l < "$tmp_log" | tr -d ' ')"
        rm -f "$tmp_log"
        emit_json "$(printf '{\
\"ts\":\"%s\",\"type\":\"sync_item\",\"host\":\"%s\",\
\"source\":\"%s\",\"dest\":\"%s\",\"status\":\"%s\",\"exit_code\":%s,\
\"symlink_follow\":true,\
\"started\":\"%s\",\"ended\":\"%s\",\"log_lines\":%s,\
\"summary_bytes\":\"%s\",\"summary_objects\":\"%s\"}\n' \
"$(json_escape "$ended")" "$(json_escape "$HOST_SHORT")" \
"$(json_escape "$SRC")" "$(json_escape "$DEST")" \
"$([[ $rc -eq 0 ]] && echo ok || echo fail)" "$rc" \
"$(json_escape "$started")" "$(json_escape "$ended")" \
"$lines" "$(json_escape "$transferred_bytes")" "$(json_escape "$objects")")"
        if [[ $rc -eq 0 ]]; then total_ok=$((total_ok+1)); else total_fail=$((total_fail+1)); fi
        ;;
    esac

    # 2) If record mode, also copy the *targets* to their *absolute* paths + build manifest
    if [[ "$SYMLINK_MODE" == "follow-and-record" ]]; then
      # Find symlinks under $SRC (files or dirs)
      # Use -L? No: we want the links themselves, so plain -type l
      while IFS= read -r LNK; do
        # Resolve to absolute
        local TARGET
        TARGET="$(realpath_portable "$LNK" 2>/dev/null || true)"
        local target_ok=false; [[ -n "$TARGET" && -e "$TARGET" ]] && target_ok=true

        # Write manifest record (JSONL)
        printf '{"ts":"%s","type":"symlink","host":"%s","link":"%s","target":"%s","target_exists":%s}\n' \
          "$(json_escape "$(timestamp_iso)")" "$(json_escape "$HOST_SHORT")" \
          "$(json_escape "$LNK")" "$(json_escape "${TARGET:-}")" \
          "$([[ "$target_ok" == true ]] && echo true || echo false)" >> "$manifest_tmp"
        symlink_records=$((symlink_records+1))

        # If target exists, upload the target to its *absolute* path in the bucket
        if [[ "$target_ok" == true ]]; then
          # Build absolute-path mirror (strip leading /)
          local TARGET_REL; TARGET_REL="$(printf '%s' "$TARGET" | sed 's#^/*##')"
          local TARGET_DEST="${REMOTE}/${TARGET_REL}"
          if [[ -d "$TARGET" ]]; then
            # directory target: sync it (could be large; this is by design — you signaled including via symlink)
            run_sync "$TARGET" "$TARGET_DEST" "$version_dir" || true
          else
            # file target: copy file (preserve versioning semantics by placing changed/removed via backup-dir;
            # rclone copyto doesn’t handle deletions; for a single file we use copyto)
            # We still JSON-log a minimal record:
            local started ended rc
            started="$(timestamp_iso)"
            set +e
            rclone copyto "$TARGET" "$TARGET_DEST" --log-level "$LOG_LEVEL"
            rc=$?; set -e; ended="$(timestamp_iso)"
            emit_json "$(printf '{\
\"ts\":\"%s\",\"type\":\"target_copy\",\"host\":\"%s\",\
\"source\":\"%s\",\"dest\":\"%s\",\"status\":\"%s\",\"exit_code\":%s,\
\"started\":\"%s\",\"ended\":\"%s\"}\n' \
"$(json_escape "$ended")" "$(json_escape "$HOST_SHORT")" \
"$(json_escape "$TARGET")" "$(json_escape "$TARGET_DEST")" \
"$([[ $rc -eq 0 ]] && echo ok || echo fail)" "$rc" \
"$(json_escape "$started")" "$(json_escape "$ended")")"
          fi
        fi
      done < <(find "$SRC" -type l 2>/dev/null || true)
    fi

  done < <(read_synclist || true)

  # 3) Upload manifest if any records
  if [[ "$symlink_records" -gt 0 ]]; then
    # Convert JSONL → JSON array to a temp file to upload (still compact)
    local manifest_arr; manifest_arr="$(mktemp -t symlinks_${HOST_SHORT}_XXXX.json)"
    printf '[' > "$manifest_arr"
    awk 'NR>1{printf ","} {printf "%s",$0}' "$manifest_tmp" >> "$manifest_arr"
    printf ']\n' >> "$manifest_arr"
    local manifest_remote="${REMOTE}/.manifests/${now}_symlinks_${HOST_SHORT}.json"
    rclone copyto "$manifest_arr" "$manifest_remote" --log-level "$LOG_LEVEL"
    rm -f "$manifest_tmp" "$manifest_arr"
    emit_json "{\"ts\":\"$(timestamp_iso)\",\"type\":\"manifest_upload\",\"host\":\"$(json_escape "$HOST_SHORT")\",\"records\":$symlink_records,\"dest\":\"$(json_escape "$manifest_remote")\"}"
  else
    rm -f "$manifest_tmp"
  fi

  # 4) Retention pruning (only if we synced something)
  if [[ "$any" -eq 1 ]]; then
    set +e
    rclone delete "${REMOTE}/.versions" --min-age "${RETENTION_HOURS}h" --fast-list --log-level NOTICE
    rclone rmdirs "${REMOTE}/.versions" --leave-root --log-level NOTICE
    set -e
  fi

  emit_json "$(printf '{\"ts\":\"%s\",\"type\":\"sync_summary\",\"host\":\"%s\",\"remote\":\"%s\",\"retention_hours\":%s}\n' \
    "$(json_escape "$(timestamp_iso)")" "$(json_escape "$HOST_SHORT")" "$(json_escape "$REMOTE")" \
    "$RETENTION_HOURS")"
}

main "$@"
