#!/bin/sh
# Подключить тему Rexilone к Millennium: ссылка на эту папку + выбор темы.
# Запускать при закрытом Steam (Millennium перезаписывает конфиг при выходе).
set -e
dir=$(cd "$(dirname "$0")" && pwd)
themes="$HOME/.local/share/Steam/millennium/themes"
config="$HOME/.config/millennium/config.json"

if pgrep -x steam >/dev/null; then
    echo "Сначала закрой Steam: steam -shutdown" >&2
    exit 1
fi

mkdir -p "$themes"
ln -sfn "$dir" "$themes/rexilone"
echo "ссылка: $themes/rexilone -> $dir"

if [ -f "$config" ]; then
    python3 - "$config" <<'PY'
import json, sys
p = sys.argv[1]
c = json.load(open(p))
c.setdefault("themes", {})["activeTheme"] = "rexilone"
json.dump(c, open(p, "w"), indent=2)
PY
    echo "тема выбрана в $config"
else
    echo "Конфига Millennium ещё нет: запусти Steam один раз, закрой и повтори,"
    echo "или выбери тему вручную: Steam → Millennium → Themes → Rexilone."
fi

[ -f "$dir/colors.css" ] || echo "colors.css создаст шелл (ThemeSync) при запуске."
