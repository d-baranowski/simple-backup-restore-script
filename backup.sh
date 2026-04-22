#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/backup.conf}"

VERBOSE=0
CLI_SOURCES=()
CLI_DEST=""

usage() {
  cat <<EOF
Usage: $0 [-s|--source DIR]... [-d|--destination DIR] [-v|--verbose] [-h|--help]

Create a compressed backup of the configured directories.

Options:
  -s, --source DIR         Source directory (may be given multiple times)
  -d, --destination DIR    Destination directory for the archive (overrides BACKUP_ROOT)
  -v, --verbose            Verbose mode (enables DEBUG logs)
  -h, --help               Show this help and exit

Long options also accept the --opt=value form.

Examples:
  $0 -s /var/www -d /backup -v
  $0 --source=/var/www --destination=/backup --verbose

Without -s / -d, values are read from the config file:
  $CONFIG_FILE
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
  # Expand short-option clusters: -vh -> -v -h, -vs /path -> -v -s /path,
  # -sFOO -> -s FOO. Stops at the first option that takes an argument;
  # the remainder of the cluster (if any) becomes its value.
  if [[ "$1" =~ ^-[a-zA-Z].+$ ]]; then
    cluster="${1#-}"
    shift
    expanded=()
    i=0
    cluster_len=${#cluster}
    while (( i < cluster_len )); do
      flag="${cluster:$i:1}"
      case "$flag" in
        s|d)
          rest="${cluster:$((i+1))}"
          if [[ -n "$rest" ]]; then
            expanded+=("-$flag" "$rest")
          else
            expanded+=("-$flag")
          fi
          i=$cluster_len
          ;;
        v|h)
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
    -s|--source)
      require_arg "$1" "${2:-}"
      CLI_SOURCES+=("$2")
      shift 2
      ;;
    --source=*)
      CLI_SOURCES+=("${1#*=}")
      shift
      ;;
    -d|--destination)
      require_arg "$1" "${2:-}"
      CLI_DEST="$2"
      shift 2
      ;;
    --destination=*)
      CLI_DEST="${1#*=}"
      shift
      ;;
    -v|--verbose)
      VERBOSE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      echo "Unexpected argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

if [[ -n "$CLI_DEST" ]]; then
  BACKUP_ROOT="$CLI_DEST"
fi

if [[ ${#CLI_SOURCES[@]} -gt 0 ]]; then
  BACKUP_SOURCES=("${CLI_SOURCES[@]}")
fi

BACKUP_ROOT="${BACKUP_ROOT:-$HOME/backups}"
LOG_DIR="${LOG_DIR:-$BACKUP_ROOT/logs}"
MAX_BACKUPS="${MAX_BACKUPS:-7}"
FOLLOW_GITIGNORE="${FOLLOW_GITIGNORE:-true}"

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

log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  local line="[$timestamp] [$level] $message"

  case "$level" in
    INFO)  echo "$line" | tee -a "$LOG_FILE" ;;
    WARN)  echo "$line" | tee -a "$LOG_FILE" >&2 ;;
    ERROR) echo "$line" | tee -a "$LOG_FILE" >&2 ;;
    DEBUG)
      if [[ $VERBOSE -eq 1 ]]; then
        echo "$line" | tee -a "$LOG_FILE"
      fi
      ;;
    *) echo "$line" | tee -a "$LOG_FILE" ;;
  esac
}

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
