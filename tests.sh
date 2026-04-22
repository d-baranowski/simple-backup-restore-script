#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PASS=0
FAIL=0
CURRENT=""

if [[ -t 1 ]]; then
  C_PASS=$'\033[32m'
  C_FAIL=$'\033[31m'
  C_SECT=$'\033[1m'
  C_RESET=$'\033[0m'
else
  C_PASS=""; C_FAIL=""; C_SECT=""; C_RESET=""
fi

pass() {
  PASS=$((PASS + 1))
  printf '  %s[ok]%s   %s\n' "$C_PASS" "$C_RESET" "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf '  %s[FAIL]%s %s\n' "$C_FAIL" "$C_RESET" "$1"
  if [[ -n "${2:-}" ]]; then
    printf '         %s\n' "$2"
  fi
  exit 1
}

section() {
  CURRENT="$1"
  printf '\n%s-- %s --%s\n' "$C_SECT" "$1" "$C_RESET"
}

contains() {
  if [[ "$1" == *"$2"* ]]; then pass "$3"; else fail "$3" "expected to contain: $2"; fi
}

not_contains() {
  if [[ "$1" != *"$2"* ]]; then pass "$3"; else fail "$3" "should not contain: $2"; fi
}

equals() {
  if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3" "expected=$2 got=$1"; fi
}

file_exists() {
  if [[ -f "$1" ]]; then pass "$2"; else fail "$2" "file not found: $1"; fi
}

run_expect() {
  local expected=$1; shift
  local desc="$1"; shift
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  if (( got == expected )); then
    pass "$desc (exit $expected)"
  else
    fail "$desc" "expected exit $expected, got $got"
  fi
}

reset_data() {
  rm -rf /tmp/sample_source /tmp/sample_source_2 /tmp/sample_dest
  mkdir -p /tmp/sample_source/sub /tmp/sample_source_2 /tmp/sample_dest
  echo hello  > /tmp/sample_source/file.txt
  echo nested > /tmp/sample_source/sub/nested.txt
  echo ignore > /tmp/sample_source/secret.log
  printf '*.log\n' > /tmp/sample_source/.gitignore
  echo other  > /tmp/sample_source_2/other.txt
}

chmod +x backup.sh restore.sh

section "help"
out=$(./backup.sh -h)
contains "$out" "Usage:" "-h prints usage"
out=$(./backup.sh --help)
contains "$out" "Usage:" "--help prints usage"

section "config-file defaults (no CLI args)"
reset_data
./backup.sh >/dev/null
count=$(find /tmp/sample_dest -maxdepth 1 -name 'backup_*.tar.gz' | wc -l | tr -d ' ')
equals "$count" "1" "archive produced from config defaults"

section "short options"
reset_data
out=$(./backup.sh -s /tmp/sample_source -d /tmp/sample_dest -v 2>&1)
contains "$out" "BACKUP START" "start logged"
contains "$out" "BACKUP END"   "end logged"
contains "$out" "[DEBUG]"      "-v enables DEBUG"

section "long options, space form"
reset_data
out=$(./backup.sh --source /tmp/sample_source --destination /tmp/sample_dest --verbose 2>&1)
contains "$out" "Staged for archiving: /tmp/sample_source" "--source / --destination space form"

section "long options, equals form"
reset_data
out=$(./backup.sh --source=/tmp/sample_source --destination=/tmp/sample_dest --verbose 2>&1)
contains "$out" "Staged for archiving: /tmp/sample_source" "--source= / --destination= equals form"

section "clustered pure flags"
out=$(./backup.sh -vh)
contains "$out" "Usage:" "-vh cluster -> -v -h -> usage shown"
out=$(./backup.sh -hv)
contains "$out" "Usage:" "-hv cluster -> usage shown (order preserved)"

section "clustered with arg-taker (next arg)"
reset_data
out=$(./backup.sh -vs /tmp/sample_source -d /tmp/sample_dest 2>&1)
contains "$out" "Verbose mode: enabled"                     "-vs: -v enabled"
contains "$out" "Staged for archiving: /tmp/sample_source"  "-vs: next arg used as source"

section "clustered attached value"
reset_data
out=$(./backup.sh -vs/tmp/sample_source -d/tmp/sample_dest 2>&1)
contains "$out" "Staged for archiving: /tmp/sample_source" "attached value via cluster"

section "multiple sources (mix short + long)"
reset_data
out=$(./backup.sh -s /tmp/sample_source --source=/tmp/sample_source_2 -d /tmp/sample_dest 2>&1)
contains "$out" "Staged for archiving: /tmp/sample_source"   "first source staged"
contains "$out" "Staged for archiving: /tmp/sample_source_2" "second source staged"

section ".gitignore filtering"
reset_data
./backup.sh -s /tmp/sample_source -d /tmp/sample_dest >/dev/null
archive=$(find /tmp/sample_dest -maxdepth 1 -name 'backup_*.tar.gz' | head -1)
listing=$(tar -tzf "$archive")
contains     "$listing" "file.txt"       "regular file archived"
contains     "$listing" "sub/nested.txt" "nested file archived"
not_contains "$listing" "secret.log"     "gitignored file excluded"

section "missing source directory"
reset_data
set +e
out=$(./backup.sh -s /does/not/exist -d /tmp/sample_dest 2>&1)
rc=$?
set -e
equals   "$rc"  "1"       "exits 1 when no valid sources"
contains "$out" "[WARN]"  "WARN for missing directory"
contains "$out" "[ERROR]" "ERROR when none remain"

section "mixed valid + missing source"
reset_data
out=$(./backup.sh -s /tmp/sample_source -s /does/not/exist -d /tmp/sample_dest -v 2>&1)
contains "$out" "[WARN]"     "WARN on missing"
contains "$out" "BACKUP END" "succeeds with the valid one"

section "parsing errors"
run_expect 1 "missing arg: --source"       ./backup.sh --source
run_expect 1 "missing arg: -s"             ./backup.sh -s
run_expect 1 "unknown long: --bogus"       ./backup.sh --bogus
run_expect 1 "unknown short: -z"           ./backup.sh -z
run_expect 1 "unknown flag in cluster -vz" ./backup.sh -vz
run_expect 1 "unexpected positional"       ./backup.sh extra

section "verbose toggle"
reset_data
out_quiet=$(./backup.sh -s /tmp/sample_source -d /tmp/sample_dest 2>&1)
not_contains "$out_quiet" "[DEBUG]" "without -v: no DEBUG"
reset_data
out_loud=$(./backup.sh -s /tmp/sample_source -d /tmp/sample_dest -v 2>&1)
contains "$out_loud" "[DEBUG]" "with -v: DEBUG present"

section "rotation (MAX_BACKUPS=2)"
reset_data
for i in 1 2 3 4; do
  ./backup.sh -s /tmp/sample_source -d /tmp/sample_dest >/dev/null
  sleep 1
done
count=$(find /tmp/sample_dest -maxdepth 1 -name 'backup_*.tar.gz' | wc -l | tr -d ' ')
equals "$count" "2" "rotation keeps MAX_BACKUPS archives"

section "log file written"
reset_data
./backup.sh -s /tmp/sample_source -d /tmp/sample_dest -v >/dev/null
log=$(find /tmp/sample_dest/logs -name 'backup_*.log' | head -1)
file_exists "$log" "per-run log file created"

printf '\n%s%d passed, %d failed%s\n' "$C_SECT" "$PASS" "$FAIL" "$C_RESET"
