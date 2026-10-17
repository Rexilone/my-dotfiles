#!/usr/bin/env bash
# Все тесты: переключатель шеллов и шелл на amane (cargo test).
#   bash tests/run.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$HOME/.cargo/bin:$PATH"
fail=0

bash "$ROOT/tests/rexilone-shell.sh" || fail=1

echo "amane"
AMANE="$ROOT/home/.config/amane"
if ! command -v amane >/dev/null || ! command -v cargo >/dev/null; then
    echo "  пропущено: нет amane или cargo (rexilone-shell use amane ставит их)"
else
    # Cargo.toml рядом с src пишет `amane compile` — с путями к библиотеке на этой машине
    [[ -f "$AMANE/Cargo.toml" ]] || AMANE_CONFIG="$AMANE" amane compile >/dev/null || fail=1
    CARGO_TARGET_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/amane/project/target" \
        cargo test --quiet --manifest-path "$AMANE/Cargo.toml" 2>&1 | grep -E "test result|FAILED|panicked|error" || true
    CARGO_TARGET_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/amane/project/target" \
        cargo test --quiet --manifest-path "$AMANE/Cargo.toml" >/dev/null 2>&1 || fail=1
fi

(( fail == 0 )) && echo "все тесты прошли" || echo "есть ошибки"
exit $fail
