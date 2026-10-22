#!/usr/bin/env bash
# Тесты движка обоев (home/.local/bin/rexilone-wallpaper): awww и swaybg подменяются заглушками,
# запущенные процессы — файлы в $T/proc, текущие обои awww — файл $T/awww-image.
#   bash tests/rexilone-wallpaper.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/home/.local/bin/rexilone-wallpaper"
PASS=0
FAIL=0

setup() {
    T="$(mktemp -d)"
    export HOME="$T/home" STUB="$T"
    mkdir -p "$T/bin" "$T/proc" "$HOME/pics"
    : > "$T/log"
    touch "$HOME/pics/a.jpg" "$HOME/pics/b.jpg"
    stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$T/bin/$1"; chmod +x "$T/bin/$1"; }
    stub pgrep '[[ -e "$STUB/proc/${@: -1}" ]] && echo 4242'
    stub pkill 'f="$STUB/proc/${@: -1}"; [[ -e "$f" ]] || exit 1; rm -f "$f"; echo "kill ${@: -1}" >> "$STUB/log"'
    stub kill 'echo "kill-pid $*" >> "$STUB/log"'
    stub setsid '[[ "$1" == -f ]] && shift; echo "start $*" >> "$STUB/log"; touch "$STUB/proc/$1"'
    stub sleep ':'
    stub awww '
case "$1" in
    query) [[ -e "$STUB/proc/awww-daemon" ]] || exit 1; echo "DP-1: 1920x1080, scale: 1, currently displaying: image: $(cat "$STUB/awww-image" 2>/dev/null)" ;;
    img) echo "awww img $2 ${3:-} ${4:-}" >> "$STUB/log"; echo "$2" > "$STUB/awww-image" ;;
esac'
    export PATH="$T/bin:/usr/bin:/bin"
}

teardown() { rm -rf "$T"; }
run() { OUT="$(bash "$SCRIPT" "$@" 2>&1)"; CODE=$?; }
proc() { [[ -e "$T/proc/$1" ]]; }
logged() { grep -qF -- "$1" "$T/log"; }
check() {
    local name="$1"; shift
    if "$@"; then
        PASS=$((PASS + 1)); printf '  ok   %s\n' "$name"
    else
        FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$name"
        printf '       вывод: %s\n       журнал: %s\n' "$OUT" "$(tr '\n' ';' < "$T/log")"
    fi
}

echo "движок обоев"

setup
run engine
check "по умолчанию — awww" test "$OUT" = awww
run start
check "start: запущен awww-daemon" proc awww-daemon
check "start: swaybg не запущен" bash -c "! test -e '$T/proc/swaybg'"
run set "$HOME/pics/a.jpg"
check "set: awww img с анимацией" logged "awww img $HOME/pics/a.jpg --transition-type grow"
run current
check "current: запомненные обои" test "$OUT" = "$HOME/pics/a.jpg"
run set "$HOME/pics/нет.jpg"
check "set: нет файла — ошибка" test "$CODE" != 0
teardown

setup
run set "$HOME/pics/a.jpg"
: > "$T/log"
run engine swaybg
check "engine swaybg: ответ" test "$OUT" = swaybg
check "engine swaybg: awww остановлен" logged "kill awww-daemon"
check "engine swaybg: swaybg с текущими обоями" logged "start swaybg -m fill -i $HOME/pics/a.jpg"
: > "$T/log"
run set "$HOME/pics/b.jpg"
check "swaybg: новые обои — новый процесс" logged "start swaybg -m fill -i $HOME/pics/b.jpg"
check "swaybg: старый процесс убран после" logged "kill-pid 4242"
check "swaybg: awww не трогали" bash -c "! grep -q 'awww img' '$T/log'"
: > "$T/log"
run engine awww
check "обратно на awww: swaybg остановлен" logged "kill swaybg"
check "обратно на awww: обои те же" logged "awww img $HOME/pics/b.jpg --transition-type none"
run engine nope
check "неизвестный движок — ошибка" test "$CODE" != 0
teardown

setup
# старая установка: состояния нет, обои знает только awww
touch "$T/proc/awww-daemon"; echo "$HOME/pics/b.jpg" > "$T/awww-image"
run current
check "без состояния — из awww query" test "$OUT" = "$HOME/pics/b.jpg"
teardown

echo "пройдено: $PASS, ошибок: $FAIL"
(( FAIL == 0 ))
