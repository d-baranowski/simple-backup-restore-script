#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/backup.conf}"

MODE="backup"
VERBOSE=0
CLI_SOURCES=()
CLI_DEST=""
CLI_ARCHIVE=""

usage() {
  cat <<EOF
Usage:
  $0 [-s DIR]... [-d DIR] [-v]                          Create a backup (default)
  $0 -r [-a PATH] [-d DIR] [-v]                         Restore from a backup
  $0 -l [-d DIR]                                        List available backups
  $0 -h                                                 Show this help

Modes:
  (default)          Back up source directories into a compressed archive.
  -r, --restore      Restore from an archive.
  -l, --list         List archives in BACKUP_ROOT and exit.

Common options:
  -v, --verbose           Verbose mode (enables DEBUG logs).
  -h, --help              Show this help.

Backup-mode options:
  -s, --source DIR        Source directory (repeatable).
  -d, --destination DIR   Where the new archive is placed (BACKUP_ROOT).

Restore-mode options:
  -a, --archive PATH      Archive to restore. Absolute, relative, or bare
                          filename looked up in BACKUP_ROOT (from config).
                          If omitted, an interactive menu is shown.
  -d, --destination DIR   Where files are extracted to (absolute or relative).
                          Directory is created if missing. Preserves the
                          archive's internal tree. If omitted, files are
                          restored to their original BACKUP_SOURCES paths.

List-mode options:
  -d, --destination DIR   Which directory to list archives from.

Long options also accept the --opt=value form. Short options may be clustered
(e.g. -vs /path, -rl).

Examples:
  $0 -s /var/www -d /backup -v
  $0 --list
  $0 --restore --archive=backup_host_2026-04-22_21-30-00.tar.gz --destination=./restored
EOF
}

require_arg() {
  if [[ -z "${2:-}" || "$2" == -* ]]; then
    echo "Option $1 requires an argument" >&2
    usage >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  if [[ "$1" =~ ^-[a-zA-Z].+$ ]]; then
    cluster="${1#-}"
    shift
    expanded=()
    i=0
    cluster_len=${#cluster}
    while (( i < cluster_len )); do
      flag="${cluster:$i:1}"
      case "$flag" in
        s|d|a)
          rest="${cluster:$((i+1))}"
          if [[ -n "$rest" ]]; then
            expanded+=("-$flag" "$rest")
          else
            expanded+=("-$flag")
          fi
          i=$cluster_len
          ;;
        r|l|v|h)
          expanded+=("-$flag")
          i=$((i+1))
          ;;
        *)
          echo "Unknown option: -$flag" >&2
          usage >&2
          exit 1
          ;;
      esac
    done
    set -- "${expanded[@]}" "$@"
  fi

  case "$1" in
    -r|--restore)     MODE="restore"; shift ;;
    -l|--list)        MODE="list"; shift ;;
    -s|--source)      require_arg "$1" "${2:-}"; CLI_SOURCES+=("$2"); shift 2 ;;
    --source=*)       CLI_SOURCES+=("${1#*=}"); shift ;;
    -d|--destination) require_arg "$1" "${2:-}"; CLI_DEST="$2"; shift 2 ;;
    --destination=*)  CLI_DEST="${1#*=}"; shift ;;
    -a|--archive)     require_arg "$1" "${2:-}"; CLI_ARCHIVE="$2"; shift 2 ;;
    --archive=*)      CLI_ARCHIVE="${1#*=}"; shift ;;
    -v|--verbose)     VERBOSE=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    --)               shift; break ;;
    -*)               echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    *)                echo "Unexpected argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ "$MODE" == "backup" && -n "$CLI_ARCHIVE" ]]; then
  echo "-a/--archive only applies to restore mode (-r)" >&2
  exit 1
fi

if [[ "$MODE" != "backup" && ${#CLI_SOURCES[@]} -gt 0 ]]; then
  echo "-s/--source only applies to backup mode" >&2
  exit 1
fi

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

# -d/--destination is context-dependent:
#   backup / list mode: overrides BACKUP_ROOT (archive storage)
#   restore mode:       used later as the extract target; BACKUP_ROOT stays as configured
if [[ "$MODE" != "restore" && -n "$CLI_DEST" ]]; then
  BACKUP_ROOT="$CLI_DEST"
fi
if [[ ${#CLI_SOURCES[@]} -gt 0 ]]; then
  BACKUP_SOURCES=("${CLI_SOURCES[@]}")
fi

BACKUP_ROOT="${BACKUP_ROOT:-$HOME/backups}"
LOG_DIR="${LOG_DIR:-$BACKUP_ROOT/logs}"
MAX_BACKUPS="${MAX_BACKUPS:-7}"
FOLLOW_GITIGNORE="${FOLLOW_GITIGNORE:-true}"

log() {
  local level="$1"; shift
  local line
  line="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
  case "$level" in
    INFO)  echo "$line" | tee -a "$LOG_FILE" ;;
    WARN)  echo "$line" | tee -a "$LOG_FILE" >&2 ;;
    ERROR) echo "$line" | tee -a "$LOG_FILE" >&2 ;;
    DEBUG) if (( VERBOSE == 1 )); then echo "$line" | tee -a "$LOG_FILE"; fi ;;
    *)     echo "$line" | tee -a "$LOG_FILE" ;;
  esac
}

collect_backups() {
  find "$BACKUP_ROOT" -maxdepth 1 -type f -name 'backup_*.tar.gz' 2>/dev/null | sort -r
}

# ===== list mode =====
if [[ "$MODE" == "list" ]]; then
  archives=()
  while IFS= read -r line; do
    archives+=("$line")
  done < <(collect_backups)

  if (( ${#archives[@]} == 0 )); then
    echo "No backups found in: $BACKUP_ROOT"
    exit 0
  fi

  printf 'Available backups in %s (%d total):\n\n' "$BACKUP_ROOT" "${#archives[@]}"
  printf '  %-8s  %-19s  %s\n' "SIZE" "DATE" "FILE"
  printf '  %-8s  %-19s  %s\n' "----" "----" "----"
  for archive in "${archives[@]}"; do
    base="$(basename "$archive")"
    size="$(du -h "$archive" | awk '{print $1}')"
    if [[ "$base" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2})_([0-9]{2})-([0-9]{2})-([0-9]{2}) ]]; then
      dt="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:${BASH_REMATCH[4]}"
    else
      dt="?"
    fi
    printf '  %-8s  %-19s  %s\n' "$size" "$dt" "$base"
  done
  exit 0
fi

# ===== restore mode =====
if [[ "$MODE" == "restore" ]]; then
  if [[ -z "$CLI_DEST" && -z "${BACKUP_SOURCES[*]:-}" ]]; then
    echo "No destination set. Pass -d DIR or define BACKUP_SOURCES in $CONFIG_FILE" >&2
    exit 1
  fi

  mkdir -p "$LOG_DIR"

  TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
  LOG_FILE="$LOG_DIR/restore_${TIMESTAMP}.log"
  TMP_EXTRACT_DIR="$(mktemp -d)"

  cleanup() {
    rm -rf "$TMP_EXTRACT_DIR"
  }
  trap cleanup EXIT

  resolve_archive() {
    local path="$1"
    if [[ -f "$path" ]]; then
      echo "$path"
    elif [[ -f "$BACKUP_ROOT/$path" ]]; then
      echo "$BACKUP_ROOT/$path"
    else
      return 1
    fi
  }

  choose_backup_interactive() {
    local archives=()
    while IFS= read -r line; do
      archives+=("$line")
    done < <(collect_backups)

    if (( ${#archives[@]} == 0 )); then
      log ERROR "No backups found in: $BACKUP_ROOT"
      exit 1
    fi

    echo "Available backups:"
    local selected
    select selected in "${archives[@]}"; do
      if [[ -n "${selected:-}" ]]; then
        BACKUP_TO_RESTORE="$selected"
        break
      fi
      echo "Invalid choice. Try again."
    done
  }

  restore_source() {
    local src="$1"
    local expanded_src extracted_src rsync_args=()

    expanded_src="${src/#\~/$HOME}"
    extracted_src="$TMP_EXTRACT_DIR/staged/${expanded_src#/}"

    if [[ ! -d "$extracted_src" ]]; then
      log WARN "Skipped $expanded_src - not present in archive"
      return 0
    fi

    mkdir -p "$expanded_src"
    rsync_args=(-a)
    if [[ "$FOLLOW_GITIGNORE" == "true" ]]; then
      rsync_args+=(--filter=':- .gitignore' --exclude='.git/' --exclude='.git')
    fi

    if rsync "${rsync_args[@]}" "$extracted_src"/ "$expanded_src"/ >>"$LOG_FILE" 2>&1; then
      log INFO "Restored directory: $expanded_src"
    else
      log ERROR "Failed to restore directory: $expanded_src"
      return 1
    fi
  }

  if [[ -n "$CLI_ARCHIVE" ]]; then
    if ! BACKUP_TO_RESTORE="$(resolve_archive "$CLI_ARCHIVE")"; then
      echo "Archive not found: $CLI_ARCHIVE" >&2
      exit 1
    fi
  else
    choose_backup_interactive
  fi

  log INFO "=== RESTORE START ==="
  log INFO "Archive: $BACKUP_TO_RESTORE"
  log DEBUG "Verbose mode: enabled"

  log INFO "Extracting archive into temporary directory: $TMP_EXTRACT_DIR"

  if tar -xzf "$BACKUP_TO_RESTORE" -C "$TMP_EXTRACT_DIR" >>"$LOG_FILE" 2>&1; then
    log INFO "Archive extracted successfully"
  else
    log ERROR "Failed to extract archive"
    exit 1
  fi

  if [[ -n "$CLI_DEST" ]]; then
    mkdir -p "$CLI_DEST"
    DEST_ABS="$(cd "$CLI_DEST" && pwd)"
    log INFO "Restoring to: $DEST_ABS"

    if [[ -d "$TMP_EXTRACT_DIR/staged" ]]; then
      if rsync -a "$TMP_EXTRACT_DIR/staged/" "$DEST_ABS/" >>"$LOG_FILE" 2>&1; then
        log INFO "Restored archive tree under: $DEST_ABS"
      else
        log ERROR "Failed to copy archive contents into $DEST_ABS"
        exit 1
      fi
    else
      log WARN "Archive has no 'staged/' root; copying raw extract tree"
      rsync -a "$TMP_EXTRACT_DIR/" "$DEST_ABS/" >>"$LOG_FILE" 2>&1
    fi
  else
    for src in "${BACKUP_SOURCES[@]}"; do
      restore_source "$src"
    done
  fi

  log INFO "=== RESTORE END ==="
  exit 0
fi

# ===== backup mode (default) =====

if [[ -z "${BACKUP_SOURCES[*]:-}" ]]; then
  echo "No source directories configured. Pass -s DIR or set BACKUP_SOURCES in $CONFIG_FILE" >&2
  exit 1
fi

mkdir -p "$BACKUP_ROOT" "$LOG_DIR"

TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
HOSTNAME_VALUE="$(hostname -s 2>/dev/null || hostname)"
BACKUP_NAME="backup_${HOSTNAME_VALUE}_${TIMESTAMP}.tar.gz"
BACKUP_PATH="$BACKUP_ROOT/$BACKUP_NAME"
LOG_FILE="$LOG_DIR/backup_${TIMESTAMP}.log"
TMP_LIST="$(mktemp)"
TMP_RSYNC_DIR="$(mktemp -d)"
STAGE_ROOT="staged"

cleanup() {
  rm -f "$TMP_LIST"
  rm -rf "$TMP_RSYNC_DIR"
}
trap cleanup EXIT

stage_source() {
  local src="$1"
  local expanded_src rel_path dest rsync_args=()

  expanded_src="${src/#\~/$HOME}"
  rel_path="${expanded_src#/}"
  dest="$TMP_RSYNC_DIR/$STAGE_ROOT/$rel_path"

  mkdir -p "$dest"

  rsync_args=(-a --delete)

  if [[ "$FOLLOW_GITIGNORE" == "true" ]]; then
    rsync_args+=(--filter=':- .gitignore' --exclude='.git/' --exclude='.git')
  fi

  if rsync "${rsync_args[@]}" "$expanded_src"/ "$dest"/ >>"$LOG_FILE" 2>&1; then
    printf '%s\n' "$STAGE_ROOT/$rel_path" >> "$TMP_LIST"
    log INFO "Staged for archiving: $expanded_src"
  else
    log ERROR "Failed to stage directory: $expanded_src"
    return 1
  fi
}

log INFO "=== BACKUP START ==="
log INFO "Config file: $CONFIG_FILE"
log INFO "Backup directory: $BACKUP_ROOT"
log INFO "Retention limit: $MAX_BACKUPS"
log INFO ".gitignore filtering: $FOLLOW_GITIGNORE"
log DEBUG "Verbose mode: enabled"

VALID_SOURCES=()

for src in "${BACKUP_SOURCES[@]}"; do
  expanded_src="${src/#\~/$HOME}"

  if [[ -d "$expanded_src" ]]; then
    VALID_SOURCES+=("$expanded_src")
    log DEBUG "Added to backup: $expanded_src"
  else
    log WARN "Skipped missing directory: $expanded_src"
  fi
done

if [[ ${#VALID_SOURCES[@]} -eq 0 ]]; then
  log ERROR "No valid source directories to back up"
  exit 1
fi

for src in "${VALID_SOURCES[@]}"; do
  stage_source "$src"
done

log INFO "Creating archive: $BACKUP_PATH"

if tar -czf "$BACKUP_PATH" -C "$TMP_RSYNC_DIR" -T "$TMP_LIST" >>"$LOG_FILE" 2>&1; then
  ARCHIVE_SIZE="$(du -h "$BACKUP_PATH" | awk '{print $1}')"
  log INFO "Backup created successfully: $BACKUP_PATH ($ARCHIVE_SIZE)"
else
  log ERROR "Failed to create archive"
  exit 1
fi

log INFO "Pruning backups above retention limit: $MAX_BACKUPS"

EXISTING_BACKUPS=()
while IFS= read -r line; do
  EXISTING_BACKUPS+=("$line")
done < <(find "$BACKUP_ROOT" -maxdepth 1 -type f -name 'backup_*.tar.gz' | sort)

BACKUP_COUNT="${#EXISTING_BACKUPS[@]}"

if (( BACKUP_COUNT > MAX_BACKUPS )); then
  TO_DELETE=$((BACKUP_COUNT - MAX_BACKUPS))

  for ((i=0; i<TO_DELETE; i++)); do
    old_backup="${EXISTING_BACKUPS[$i]}"
    rm -f "$old_backup"
    log INFO "Deleted old backup: $old_backup"
  done
else
  log DEBUG "No old backups to prune"
fi

log INFO "=== BACKUP END ==="
