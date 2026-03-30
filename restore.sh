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
FOLLOW_GITIGNORE="${FOLLOW_GITIGNORE:-true}"

if [[ -z "${BACKUP_SOURCES[*]:-}" ]]; then
  echo "Brak katalogów do przywrócenia. Ustaw BACKUP_SOURCES w $CONFIG_FILE" >&2
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

log() {
  local msg="$1"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" | tee -a "$LOG_FILE"
}

choose_backup() {
  mapfile -t AVAILABLE_BACKUPS < <(
    find "$BACKUP_ROOT" -maxdepth 1 -type f -name 'backup_*.tar.gz' | sort -r
  )

  if [[ ${#AVAILABLE_BACKUPS[@]} -eq 0 ]]; then
    log "Brak backupów w katalogu: $BACKUP_ROOT"
    exit 1
  fi

  echo "Dostępne backupy:"
  select selected_backup in "${AVAILABLE_BACKUPS[@]}"; do
    if [[ -n "${selected_backup:-}" ]]; then
      BACKUP_TO_RESTORE="$selected_backup"
      break
    fi
    echo "Nieprawidłowy wybór. Spróbuj ponownie."
  done
}

restore_source() {
  local src="$1"
  local expanded_src extracted_src rsync_args=()

  expanded_src="${src/#\~/$HOME}"
  extracted_src="$TMP_EXTRACT_DIR/${expanded_src#/}"

  if [[ ! -d "$extracted_src" ]]; then
    log "Pominięto $expanded_src - brak tego katalogu w archiwum"
    return 0
  fi

  mkdir -p "$expanded_src"

  rsync_args=(-a)

  if [[ "$FOLLOW_GITIGNORE" == "true" ]]; then
    rsync_args+=(--filter=':- .gitignore' --exclude='.git/' --exclude='.git')
  fi

  if rsync "${rsync_args[@]}" "$extracted_src"/ "$expanded_src"/ >>"$LOG_FILE" 2>&1; then
    log "Przywrócono katalog: $expanded_src"
  else
    log "Błąd podczas przywracania katalogu: $expanded_src"
    return 1
  fi
}

log "=== START PRZYWRACANIA ==="
log "Plik konfiguracyjny: $CONFIG_FILE"
log "Katalog backupów: $BACKUP_ROOT"
log "Obsługa .gitignore: $FOLLOW_GITIGNORE"

choose_backup

log "Wybrany backup: $BACKUP_TO_RESTORE"
log "Rozpakowywanie archiwum do katalogu tymczasowego: $TMP_EXTRACT_DIR"

if tar -xzf "$BACKUP_TO_RESTORE" -C "$TMP_EXTRACT_DIR" >>"$LOG_FILE" 2>&1; then
  log "Archiwum rozpakowane poprawnie"
else
  log "Błąd podczas rozpakowywania archiwum"
  exit 1
fi

for src in "${BACKUP_SOURCES[@]}"; do
  restore_source "$src"
done

log "=== KONIEC PRZYWRACANIA ==="
