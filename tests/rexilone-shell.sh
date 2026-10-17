#!/usr/bin/env bash
# Тесты переключателя шеллов (home/.local/bin/rexilone-shell).
# Настоящие qs, amane, niri, pgrep и pkill подменяются заглушками: запущенные процессы — файлы в $T/proc.
#   bash tests/rexilone-shell.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/home/.local/bin/rexilone-shell"
PASS=0
FAIL=0

setup() {
    T="$(mktemp -d)"
    export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_CACHE_HOME="$T/home/.cache"
    export STUB="$T" NIRI_SOCKET=""
    mkdir -p "$T/bin" "$T/proc" "$XDG_CONFIG_HOME/amane/src" "$XDG_CACHE_HOME/amane"
    echo 'fn main() {}' > "$XDG_CONFIG_HOME/amane/src/main.rs"
    : > "$T/log"
    BIN="$XDG_CACHE_HOME/amane/amane-shell"

    stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$T/bin/$1"; chmod +x "$T/bin/$1"; }
    # имя процесса: для -f — полный путь (как в cmdline), иначе базовое имя
    stub pgrep 'n="${@: -1}"; [[ -e "$STUB/proc/$(printf %s "$n" | tr / _)" ]]'
    stub pkill 'n="${@: -1}"; f="$STUB/proc/$(printf %s "$n" | tr / _)"; [[ -e "$f" ]] || exit 1; rm -f "$f"; echo "kill $n" >> "$STUB/log"'
    # amane-crashes: шелл amane падает сразу после запуска
    stub setsid '[[ "$1" == -f ]] && shift; p="$1"; [[ "$p" == /* ]] || p="$(basename "$p")"; echo "start $*" >> "$STUB/log"; [[ "$p" == */amane-shell && -e "$STUB/amane-crashes" ]] && exit 0; touch "$STUB/proc/$(printf %s "$p" | tr / _)"'
    stub qs 'if [[ "$1" == ipc ]]; then echo "qs $*" >> "$STUB/log"; fi'
    stub notify-send 'echo "notify ${@: -1}" >> "$STUB/log"'
    stub sleep ':'
    stub amane '
case "$1" in
    compile)
        echo "compile" >> "$STUB/log"
        [[ -e "$STUB/compile-fails" ]] && exit 1
        touch "$XDG_CACHE_HOME/amane/amane-shell"; chmod +x "$XDG_CACHE_HOME/amane/amane-shell" ;;
    ipc)
        shift 2
        echo "amane ipc $*" >> "$STUB/log"
        case "$1" in launcher|power|clipboard|wallpaper) echo ok ;; *) echo "no handler named $1" ;; esac ;;
esac'
    export PATH="$T/bin:/usr/bin:/bin"
}

teardown() { rm -rf "$T"; }

run() { OUT="$(bash "$SCRIPT" "$@" 2>&1)"; CODE=$?; }

proc() { [[ -e "$T/proc/$(printf %s "$1" | tr / _)" ]]; }

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

t_default_is_quickshell() {
    setup
    run current
    check "по умолчанию выбран quickshell" test "$OUT" = quickshell
    run start
    check "start запускает qs" proc qs
    check "amane не запущен" not proc "$BIN"
    teardown
}

t_use_amane_switches() {
    setup
    touch "$T/proc/qs"
    run use amane
    check "use amane: код 0" test "$CODE" = 0
    check "выбор сохранён" test "$(cat "$XDG_CONFIG_HOME/rexilone/shell")" = amane
    check "qs остановлен" not proc qs
    check "amane собран" logged compile
    check "amane запущен" proc "$BIN"
    run running
    check "running = amane" test "$OUT" = amane
    teardown
}

t_build_fail_keeps_quickshell() {
    setup
    touch "$T/proc/qs" "$T/compile-fails"
    run use amane
    check "сборка не удалась: ошибка" test "$CODE" != 0
    check "выбор не поменялся" test "$(bash "$SCRIPT" current)" = quickshell
    check "qs продолжает работать" proc qs
    check "есть уведомление" logged "notify"
    teardown
}

t_start_falls_back() {
    setup
    mkdir -p "$XDG_CONFIG_HOME/rexilone"; echo amane > "$XDG_CONFIG_HOME/rexilone/shell"
    touch "$T/compile-fails"
    run start
    check "amane не собрался — запущен qs" proc qs
    check "предупреждение о запасном шелле" logged "запускаю Quickshell"
    teardown
}

t_amane_crash_falls_back() {
    setup
    touch "$T/proc/qs" "$T/amane-crashes"
    run use amane
    check "amane упал при запуске — снова qs" proc qs
    check "предупреждение о падении" logged "запускаю Quickshell"
    teardown
}

t_installs_amane_on_demand() {
    setup
    mv "$T/bin/amane" "$T/amane.real"
    # cargo install кладёт amane в ~/.cargo/bin
    stub cargo 'echo "cargo $*" >> "$STUB/log"; mkdir -p "$HOME/.cargo/bin"; cp "$STUB/amane.real" "$HOME/.cargo/bin/amane"'
    touch "$T/proc/qs"
    run use amane
    check "amane ставится через cargo (закреплённая версия)" logged "cargo install --locked --git https://github.com/MystiaFin/amane --rev"
    check "после установки — запущен" proc "$BIN"
    teardown
}

t_no_rebuild_when_fresh() {
    setup
    touch "$BIN"; chmod +x "$BIN"
    touch -d '-1 hour' "$XDG_CONFIG_HOME/amane/src/main.rs"
    mkdir -p "$XDG_CONFIG_HOME/rexilone"; echo amane > "$XDG_CONFIG_HOME/rexilone/shell"
    run start
    check "свежая сборка: compile не вызывается" not logged compile
    check "amane запущен" proc "$BIN"
    touch "$XDG_CONFIG_HOME/amane/src/main.rs"
    touch -d '-1 minute' "$BIN"
    rm -f "$T/proc/"*
    run start
    check "исходники новее: пересборка" logged compile
    teardown
}

t_use_quickshell_back() {
    setup
    mkdir -p "$XDG_CONFIG_HOME/rexilone"; echo amane > "$XDG_CONFIG_HOME/rexilone/shell"
    touch "$BIN" "$T/proc/$(printf %s "$BIN" | tr / _)"
    run use quickshell
    check "amane остановлен" not proc "$BIN"
    check "qs запущен" proc qs
    check "выбор = quickshell" test "$(bash "$SCRIPT" current)" = quickshell
    teardown
}

t_toggle() {
    setup
    run toggle
    check "toggle: quickshell → amane" test "$(bash "$SCRIPT" current)" = amane
    run toggle
    check "toggle: amane → quickshell" test "$(bash "$SCRIPT" current)" = quickshell
    teardown
}

t_ipc_routes() {
    setup
    touch "$T/proc/qs"
    run ipc launcher toggle
    check "ipc в Quickshell" logged "qs ipc call launcher toggle"
    rm -f "$T/proc/qs"; touch "$BIN" "$T/proc/$(printf %s "$BIN" | tr / _)"
    run ipc launcher toggle
    check "ipc в amane" logged "amane ipc launcher toggle"
    check "ответ amane выведен" test "$OUT" = ok
    run ipc plugins reload
    check "нет в amane: ошибка" test "$CODE" != 0
    check "нет в amane: уведомление" logged "в amane пока нет «plugins»"
    teardown
}

t_bad_args() {
    setup
    run use sway
    check "неизвестный шелл: код 2" test "$CODE" = 2
    run frobnicate
    check "неизвестная команда: код 2" test "$CODE" = 2
    run ipc
    check "ipc без цели: код 2" test "$CODE" = 2
    teardown
}

t_garbage_choice() {
    setup
    mkdir -p "$XDG_CONFIG_HOME/rexilone"; echo 'rm -rf /' > "$XDG_CONFIG_HOME/rexilone/shell"
    run current
    check "мусор в файле выбора → quickshell" test "$OUT" = quickshell
    teardown
}

echo "rexilone-shell"
t_default_is_quickshell
t_use_amane_switches
t_build_fail_keeps_quickshell
t_start_falls_back
t_amane_crash_falls_back
t_installs_amane_on_demand
t_no_rebuild_when_fresh
t_use_quickshell_back
t_toggle
t_ipc_routes
t_bad_args
t_garbage_choice
echo "пройдено: $PASS, ошибок: $FAIL"
(( FAIL == 0 ))
