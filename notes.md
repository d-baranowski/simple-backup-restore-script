
1

2

3

4

5

6

7

8

9

10

11

12

13

14

15

16

17

18

1
/ 18

130%

📥 Pobierz PDF
Lekcja 12: Bash w praktyce: od podstaw do
zaawansowania
Informacje o lekcji
Czas trwania: 180 minut
Poziom trudności: Średniozaawansowany
Grupa docelowa: Programiści, administratorzy systemów, DevOps oraz wszyscy
zainteresowani zaawansowaną automatyzacją skryptów Bash
Cele lekcji
Na tej lekcji studenci poznają:
Wymagania wstępne
Utrwalenie poprzedniego materiału
Zanim przejdziemy dalej, upewnijmy się, że dobrze rozumiemy podstawowe koncepcje.
Test wiedzy: analiza przykładowego skryptu

1. Zaawansowaną obsługę parametrów wiersza poleceń (getopts i case)
2. Systemy logowania na różnych poziomach (INFO, WARN, ERROR, DEBUG)
3. Bezpieczne zarządzanie plikami tymczasowymi i funkcje czyszczące (trap)
4. Zarządzanie procesami w tle, pliki PID i kontrolę żywotności procesów
5. Obsługę błędów i mechanizmy przywracania spójności (cleanup)
Ukończenie lekcji 11 (Bash: podstawy, zmienne, pętle, funkcje)
Zrozumienie struktury skryptów Bash i podstawowych poleceń systemowych
Umiejętność pracy z plikami i katalogami
Praktyka z instrukcjami warunkowymi i pętlami
# !/bin/bash

# Prosty skrypt do pracy z plikami

log_file="script.log"
files_dir="./files"
Wyjaśnienie elementów:
Nowy materiał: ulepszanie skryptów

1. Obsługa parametrów wiersza poleceń
Do tej pory używaliśmy prostego podejścia do parametrów ( $1 , $2 ). Teraz poznamy bardziej
elastyczny sposób:

# Funkcja do logowania

log_message() {
echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$log_file"
}

# Tworzymy katalog, jeśli nie istnieje

if [[ ! -d "$files_dir" ]]; then
mkdir -p "$files_dir"
log_message "Utworzono katalog $files_dir"
fi

# Przetwarzanie plików

for file in "$files_dir"/*.txt; do
if [[ -f "$file" ]]; then
echo "Przetwarzanie pliku: $file"

# Kod przetwarzania pliku

fi
done

1. Shebang ( #!/bin/bash ) – wskazuje, jakiego interpretera użyć
2. Zmienne – przechowują ścieżki do plików
3. Funkcje – organizują kod w wielokrotnie używane bloki
4. Instrukcje warunkowe i pętle – kontrolują przepływ wykonania
# !/bin/bash

# Wartości domyślne

verbose=0
output_file="output.txt"

# Analiza parametrów

while [[ $# -gt 0 ]]; do
case "$1" in
Dlaczego to jest lepsze?
Jak to działa (wyjaśnienie logiki):
Pętla while [[ $# -gt 0 ]] iteruje przez wszystkie argumenty ( $# to liczba argumentów).
W każdej iteracji case sprawdza wartość $1 (aktualny argument). Polecenie shift usuwa
przetworzony argument z listy, a shift 2 przesuwa się o 2 pozycje (dla opcji z wartością). To
jest elastyczne podejście, które pozwala na dowolną kolejność argumentów, w przeciwieństwie
do pozycyjnych argumentów z lekcji 11.
2. Ulepszone logowanie
Logowanie na różnych poziomach (INFO, WARN, ERROR, DEBUG) to standard w
produkcyjnych skryptach. Pozwala na:
-v|--verbose)
verbose=1
shift
;;
-o|--output)
output_file="$2"
shift 2
;;
-h|--help)
echo "Użycie: $0 [-v|--verbose] [-o|--output plik]"
exit 0
;;
*)
echo "Nieznany parametr: $1"
exit 1
;;
esac
done

# Wykorzystanie parametrów

if [[ $verbose -eq 1 ]]; then
echo "Tryb szczegółowy włączony"
echo "Plik wyjściowy: $output_file"
fi
Obsługa długich opcji ( --verbose zamiast -v )
Bardziej czytelny kod
Łatwo dodać nowe parametry
Filtrowanie wiadomości w zależności od poziomu ważności
Wyjaśnienie działania:
3. Bezpieczna praca z plikami i zasobami
Pracując z plikami tymczasowymi, ważne jest zagwarantowanie ich czyszczenia nawet jeśli
skrypt zawiedzie lub zostanie przerwany. To zapobiega zaśmiecaniu dysku. Polecenie trap
przechwytuje sygnały systemowe (EXIT, INT, TERM) i uruchamia funkcję czyszczącą.
Scenariusz z życia DevOps:
Skrypt przetwarza dane, ale zostaje przerwany (Ctrl+C). Bez trap plik tymczasowy zostaje na
dysku. Z trap — jest automatycznie usuwany.
Rozdzielenie komunikatów normalnych (stdout) od błędów (stderr) — błędy idą do >&2
Warunkowe wyświetlanie DEBUG tylko w trybie debugowania
Łatwe tworzenie logów do analiz i troubleshootingu
# !/bin/bash

# Funkcja do logowania na różnych poziomach

log() {
local level="$1"
shift
local message="$*"
local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
case "$level" in
INFO) echo "[$timestamp] [INFO] $message" ;;
ERROR) echo "[$timestamp] [ERROR] $message" >&2 ;;
DEBUG) [[ $verbose -eq 1 ]] && echo "[$timestamp] [DEBUG] $message"
;;
esac
}

# Przykłady użycia

log INFO "Program uruchomiony"
log ERROR "Plik nie znaleziony"
log DEBUG "Wartość zmiennej: $var"
Argumenty: level to poziom (INFO/ERROR/DEBUG), a $* to reszta komunikatu
>&2 przekierowuje output do stderr (standardowy błąd) — to standard dla komunikatów o
błędach
[[ $verbose -eq 1 ]] && to warunkowa semantyka: DEBUG wypisuje się tylko jeśli
zmienna verbose wynosi 1
Wyjaśnienie:
Praktyczny przykład: ulepszona kopia zapasowa
Backupy to kluczowe zadanie w DevOps. Poniższy skrypt demonstruje najlepsze praktyki:
# !/bin/bash

# Bezpieczne tworzenie pliku tymczasowego

temp_file=$(mktemp)

# Czyszczenie przy zakończeniu

cleanup() {
rm -f "$temp_file"
log INFO "Pliki tymczasowe zostały usunięte"
}

# Rejestracja funkcji czyszczącej

trap cleanup EXIT

# Bezpieczna praca z plikiem tymczasowym

echo "Dane" > "$temp_file"

# Przetwarzanie

mktemp tworzy plik z losową nazwą w /tmp — bezpieczniej niż ręczne nazwy
trap cleanup EXIT rejestruje funkcję czyszczącą, która uruchomi się zawsze na koniec
trap obsługuje sygnały: EXIT (normalny koniec), INT (Ctrl+C), TERM (sygnał zamknięcia)
Sprawdzanie warunków wstępnych (katalogi istnieją?)
Logowanie każdego kroku
Obsługa błędów na każdym etapie
Struktura z funkcjami i główną logiką
# !/bin/bash

# backup.sh - Ulepszony skrypt tworzenia kopii zapasowych

# Konfiguracja

source_dir="/var/www"
backup_dir="/backup"
date_format=$(date +%Y%m%d_%H%M%S)
backup_file="backup_${date_format}.tar.gz"
Wyjaśnienie kluczowych elementów:

# Funkcja do sprawdzania katalogów

check_directories() {
local dirs=("$source_dir" "$backup_dir")
for dir in "${dirs[@]}"; do
if [[ ! -d "$dir" ]]; then
log ERROR "Katalog nie istnieje: $dir"
return 1
fi
done
return 0
}

# Funkcja do tworzenia kopii zapasowej

create_backup() {
log INFO "Rozpoczęcie tworzenia kopii zapasowej..."
if tar -czf "$backup_dir/$backup_file" -C "$source_dir" .; then
log INFO "Kopia zapasowa została pomyślnie utworzona: $backup_file"
return 0
else
log ERROR "Błąd podczas tworzenia kopii zapasowej"
return 1
fi
}

# Główna logika

main() {
if ! check_directories; then
exit 1
fi
if create_backup; then
log INFO "Proces zakończony sukcesem"
else
log ERROR "Wystąpił problem"
exit 1
fi
}

# Uruchomienie programu

main
