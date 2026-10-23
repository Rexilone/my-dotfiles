#!/usr/bin/env bash
# Тесты запуска шелла (home/.local/bin/rexilone-shell).
# Настоящие qs, niri, pgrep и pkill подменяются заглушками: запущенные процессы — файлы в $T/proc.
#   bash tests/rexilone-shell.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/home/.local/bin/rexilone-shell"
PASS=0
FAIL=0

setup() {
    T="$(mktemp -d)"
    export HOME="$T/home" STUB="$T" NIRI_SOCKET="" XDG_RUNTIME_DIR="$T" XDG_CACHE_HOME="$T/cache"
    mkdir -p "$T/bin" "$T/proc"
    : > "$T/log"
    stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$T/bin/$1"; chmod +x "$T/bin/$1"; }
    stub pgrep '[[ -e "$STUB/proc/${@: -1}" ]]'
    stub pkill 'f="$STUB/proc/${@: -1}"; [[ -e "$f" ]] || exit 1; rm -f "$f"; echo "kill ${@: -1}" >> "$STUB/log"'
    stub setsid '[[ "$1" == -f ]] && shift; echo "start $*" >> "$STUB/log"; touch "$STUB/proc/$(basename "$1")"'
    stub qs 'echo "qs $*" >> "$STUB/log"'
    stub sleep ':'
    export PATH="$T/bin:/usr/bin:/bin"
}

teardown() { rm -rf "$T"; }

run() { OUT="$(bash "$SCRIPT" "$@" 2>&1)"; CODE=$?; }

proc() { [[ -e "$T/proc/$1" ]]; }

check() {
    local name="$1"; shift
    if "$@"; then
        PASS=$((PASS + 1)); printf '  ok   %s\n' "$name"
    else
        FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$name"
        printf '       вывод: %s\n       журнал: %s\n' "$OUT" "$(tr '\n' ';' < "$T/log")"
    fi
}

logged() { grep -qF -- "$1" "$T/log"; }
not() { ! "$@"; }

t_start_stop() {
    setup
    run
    check "не запущен → none" test "$OUT" = none
    run start
    check "start запускает qs" proc qs
    run start
    check "второй start не плодит qs" test "$(grep -c '^start qs$' "$T/log")" = 1
    check "start поднимает сторожа" logged "rexilone-shell watchdog"
    run stop
    check "stop останавливает qs" not proc qs
    check "stop: сторож не поднимает шелл" test -e "$T/rexilone-shell.stopped"
    run restart
    check "restart поднимает qs" proc qs
    teardown
}

t_ipc() {
    setup
    run ipc launcher toggle
    check "ipc в Quickshell" logged "qs ipc call launcher toggle"
    teardown
}

t_bad_args() {
    setup
    run frobnicate
    check "неизвестная команда: код 2" test "$CODE" = 2
    run ipc
    check "ipc без цели: код 2" test "$CODE" = 2
    teardown
}

echo "rexilone-shell"
t_start_stop
t_ipc
t_bad_args
echo "пройдено: $PASS, ошибок: $FAIL"
(( FAIL == 0 ))
