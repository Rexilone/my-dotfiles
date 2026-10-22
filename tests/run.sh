#!/usr/bin/env bash
# Все тесты: запуск шелла и обои.
#   bash tests/run.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

bash "$ROOT/tests/rexilone-shell.sh" || fail=1
bash "$ROOT/tests/rexilone-wallpaper.sh" || fail=1

(( fail == 0 )) && echo "все тесты прошли" || echo "есть ошибки"
exit $fail
