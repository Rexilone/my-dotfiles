#!/usr/bin/env bash
# Тесты запуска шелла (home/.local/bin/rexilone-shell).
# Настоящие qs, niri, pgrep и kill подменяются заглушками: запущенные процессы — файлы в $T/proc
# (имя процесса, внутри — его номер).
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
    # pgrep -x 'qs|quickshell' — номера живых процессов с такими именами
    stub pgrep 'ok=1; for n in ${@: -1}; do :; done; IFS="|" read -ra ns <<< "${@: -1}"; for n in "${ns[@]}"; do [[ -e "$STUB/proc/$n" ]] && { cat "$STUB/proc/$n"; ok=0; }; done; exit $ok'
    # kill [-сигнал] номер… — убрать процессы; номер из $STUB/unkillable не умирает (завис в ядре)
    stub kill 'for a; do [[ $a == -* ]] && continue; grep -qxF "$a" "$STUB/unkillable" 2>/dev/null && continue; for f in "$STUB"/proc/*; do [[ -e $f && $(cat "$f") == "$a" ]] && { rm -f "$f"; echo "kill $(basename "$f")" >> "$STUB/log"; }; done; done; exit 0'
    stub setsid '[[ "$1" == -f ]] && shift; echo "start $*" >> "$STUB/log"; n=$(basename "$1"); [[ -e "$STUB/proc/$n" ]] && n="$n.$RANDOM"; echo $((RANDOM + 1000)) > "$STUB/proc/$n"'
    stub notify-send 'echo "notify $*" >> "$STUB/log"'
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

# шелл завис в драйвере и не умирает от SIGKILL: stop не ждёт его вечно, start запускает новый
t_stuck() {
    setup
    run start
    cat "$T/proc/qs" > "$T/unkillable"
    run stop
    check "зависший: stop предупреждает" logged "notify"
    run start
    check "зависший: start запускает новый qs" test "$(grep -c '^start qs$' "$T/log")" = 2
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
t_stuck
t_ipc
t_bad_args
echo "пройдено: $PASS, ошибок: $FAIL"
(( FAIL == 0 ))
