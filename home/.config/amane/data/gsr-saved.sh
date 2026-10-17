#!/bin/sh
# вызывается gpu-screen-recorder после сохранения: $1 — файл, $2 — regular|replay
file="$1"
case "$2" in
    replay) title="Повтор сохранён" ;;
    *)      title="Запись сохранена" ;;
esac
size=$(du -h "$file" 2>/dev/null | cut -f1)
thumb="${XDG_RUNTIME_DIR:-/tmp}/gsr-thumb.png"
ffmpeg -loglevel error -y -ss 0.5 -i "$file" -frames:v 1 -vf scale=320:-1 "$thumb" 2>/dev/null || thumb=media-record

action=$(notify-send -a "Recorder" -i "$thumb" \
    -A open="Открыть" -A folder="Папка" -A copy="Копировать путь" \
    "$title" "$(basename "$file") · $size")

case "$action" in
    open)   xdg-open "$file" ;;
    folder) xdg-open "$(dirname "$file")" ;;
    copy)   printf '%s' "$file" | wl-copy ;;
esac
