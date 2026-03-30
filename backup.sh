#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/backup.conf}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Brak pliku konfiguracyjnego: $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

BACKUP_ROOT="${BACKUP_ROOT:-$HOME/backups}"
LOG_DIR="${LOG_DIR:-$BACKUP_ROOT/logs}"
MAX_BACKUPS="${MAX_BACKUPS:-7}"
FOLLOW_GITIGNORE="${FOLLOW_GITIGNORE:-true}"

if [[ -z "${BACKUP_SOURCES[*]:-}" ]]; then
  echo "Brak katalogów do backupu. Ustaw BACKUP_SOURCES w $CONFIG_FILE" >&2
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
  local msg="$1"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" | tee -a "$LOG_FILE"
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
    log "Przygotowano do archiwizacji: $expanded_src"
  else
    log "Błąd podczas przygotowania katalogu: $expanded_src"
    return 1
  fi
}

log "=== START BACKUPU ==="
log "Plik konfiguracyjny: $CONFIG_FILE"
log "Katalog backupów: $BACKUP_ROOT"
log "Limit kopii: $MAX_BACKUPS"
log "Obsługa .gitignore: $FOLLOW_GITIGNORE"

VALID_SOURCES=()

for src in "${BACKUP_SOURCES[@]}"; do
  expanded_src="${src/#\~/$HOME}"

  if [[ -d "$expanded_src" ]]; then
    VALID_SOURCES+=("$expanded_src")
    log "Dodano do backupu: $expanded_src"
  else
    log "Pominięto nieistniejący katalog: $expanded_src"
  fi
done

if [[ ${#VALID_SOURCES[@]} -eq 0 ]]; then
  log "Brak poprawnych katalogów do wykonania backupu"
  exit 1
fi

for src in "${VALID_SOURCES[@]}"; do
  stage_source "$src"
done

log "Tworzenie archiwum: $BACKUP_PATH"

if tar -czf "$BACKUP_PATH" -C "$TMP_RSYNC_DIR" -T "$TMP_LIST" >>"$LOG_FILE" 2>&1; then
  ARCHIVE_SIZE="$(du -h "$BACKUP_PATH" | awk '{print $1}')"
  log "Backup utworzony poprawnie: $BACKUP_PATH ($ARCHIVE_SIZE)"
else
  log "Błąd podczas tworzenia backupu"
  exit 1
fi

log "Usuwanie starych backupów ponad limit: $MAX_BACKUPS"

mapfile -t EXISTING_BACKUPS < <(
  find "$BACKUP_ROOT" -maxdepth 1 -type f -name 'backup_*.tar.gz' | sort
)

BACKUP_COUNT="${#EXISTING_BACKUPS[@]}"

if (( BACKUP_COUNT > MAX_BACKUPS )); then
  TO_DELETE=$((BACKUP_COUNT - MAX_BACKUPS))

  for ((i=0; i<TO_DELETE; i++)); do
    old_backup="${EXISTING_BACKUPS[$i]}"
    rm -f "$old_backup"
    log "Usunięto stary backup: $old_backup"
  done
else
  log "Nie ma starych backupów do usunięcia"
fi

log "=== KONIEC BACKUPU ==="
