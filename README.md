# Backup Script — Zadanie domowe 2

Skrypt kopii zapasowych z opcjami CLI, logowaniem na poziomach i sprzątaniem plików tymczasowych.

## Użycie

```bash
./backup.sh -s /var/www -d /backup -v    # backup z verbose
./backup.sh -h                            # pomoc
```

| krótka | długa | znaczenie |
|---|---|---|
| `-s DIR` | `--source DIR` / `--source=DIR` | katalog źródłowy (można podać wielokrotnie) |
| `-d DIR` | `--destination DIR` / `--destination=DIR` | katalog docelowy |
| `-v` | `--verbose` | logi DEBUG |
| `-h` | `--help` | pomoc |

Krótkie flagi można klastrować (`-vh`, `-vs /path`, `-vs/path`). Bez `-s` / `-d` wartości pochodzą z `backup.conf`.

## Przywracanie

```bash
./restore.sh    # interaktywny wybór archiwum z BACKUP_ROOT
```

## Testy

```bash
./tests.sh      # 33 testy, przerywa na pierwszym błędzie
```

Ręczny test z treści zadania:

```bash
chmod +x backup.sh
mkdir -p /tmp/test_source /tmp/test_backup
echo "test" > /tmp/test_source/file.txt
./backup.sh -s /tmp/test_source -d /tmp/test_backup -v
ls -la /tmp/test_backup/
```

## Spełnienie wymagań Zadania 2

| Wymaganie | Gdzie w kodzie |
|---|---|
| Obsługa opcji (`getopts` lub `case` / `shift`) | `backup.sh` — pętla `while / case / shift` z ekspansją klastrów |
| `-s`, `-d`, `-v`, `-h` | wszystkie obecne, plus warianty długie i forma `=` |
| `log()` z poziomami INFO / WARN / ERROR / DEBUG | funkcja `log()` w `backup.sh` |
| `set -euo pipefail` | `backup.sh:3` (użyte jako `-Eeuo pipefail` — nadzbiór) |
| `trap cleanup EXIT` | `backup.sh` — zwalnia `mktemp` plik i katalog rsync |
| Sprawdzanie katalogów `[[ -d ... ]]` | `backup.sh` — walidacja źródeł przed archiwizacją |
