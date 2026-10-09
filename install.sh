#!/usr/bin/env bash
# Установка рабочего окружения Rexilone (niri + Quickshell) на Arch Linux.
#
#   ./install.sh                 пакеты + конфиги
#   ./install.sh --with-steam    + Steam и тема «Rexilone» (Millennium)
#   ./install.sh --with-tablet   + OpenTabletDriver (рабочая область планшета)
#   ./install.sh --with-printers + печать и сканирование (CUPS)
#   ./install.sh --all           всё сразу
#   ./install.sh --link-only     только конфиги (без пакетов)
#   ./install.sh --dry-run       показать, что будет сделано
#
# Конфиги не копируются, а ставятся ссылками на эту папку: правишь в ~/my-dotfiles —
# сразу работает. Всё, что было на месте ссылок, переносится в ~/.dots-backup/<дата>/.
set -euo pipefail

DOTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP="$HOME/.dots-backup/$(date +%Y%m%d-%H%M%S)"
STEAM=0 TABLET=0 PRINTERS=0 PACKAGES=1 DRY=0

for a in "$@"; do
    case "$a" in
        --with-steam) STEAM=1 ;;
        --with-tablet) TABLET=1 ;;
        --with-printers) PRINTERS=1 ;;
        --all) STEAM=1 TABLET=1 PRINTERS=1 ;;
        --link-only) PACKAGES=0 ;;
        --dry-run) DRY=1 ;;
        -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Неизвестный параметр: $a (см. --help)" >&2; exit 1 ;;
    esac
done

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
run() { if (( DRY )); then printf '  [dry-run] %s\n' "$*"; else "$@"; fi; }
list() { grep -hvE '^\s*(#|$)' "$@" 2>/dev/null || true; }

[[ $EUID -eq 0 ]] && { echo "Запускайте от своего пользователя, не от root (sudo спросят, когда нужно)." >&2; exit 1; }
[[ -f /etc/arch-release ]] || { echo "Это установщик для Arch Linux. Для NixOS — см. nixos/README.md" >&2; exit 1; }

# ─────────────────────────── пакеты
if (( PACKAGES )); then
    bold "Пакеты"

    if (( STEAM )) && ! grep -q '^\[multilib\]' /etc/pacman.conf; then
        info "Steam нужен репозиторий multilib — включаю в /etc/pacman.conf"
        run sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
        run sudo pacman -Sy
    fi

    pkgs=( $(list "$DOTS/packages/arch.txt") )
    (( STEAM )) && pkgs+=( $(list "$DOTS/packages/steam.txt") )
    (( PRINTERS )) && pkgs+=( $(list "$DOTS/packages/printers.txt") )
    # -Syu, а не -S: частичное обновление в Arch ломает библиотеки
    run sudo pacman -Syu --needed --noconfirm "${pkgs[@]}"

    # AUR-помощник. paru-bin не годится: это готовый бинарник, и после обновления
    # pacman он падает с «libalpm.so.N: cannot open shared object file». Поэтому
    # paru собирается из исходников под текущий libalpm; сломанный — пересобирается.
    works() { command -v "$1" >/dev/null && "$1" --version >/dev/null 2>&1; }
    if ! works paru && ! works yay; then
        info "Собираю paru из исходников (AUR)"
        for p in paru-bin paru-bin-debug paru; do
            if pacman -Qq "$p" >/dev/null 2>&1; then run sudo pacman -Rdd --noconfirm "$p"; fi
        done
        run sudo pacman -S --needed --noconfirm base-devel git
        tmp=$(mktemp -d)
        run git clone --depth 1 https://aur.archlinux.org/paru.git "$tmp/paru"
        (( DRY )) || (cd "$tmp/paru" && makepkg -si --noconfirm)
        rm -rf "$tmp"
    fi
    if works paru; then AUR=paru; elif works yay; then AUR=yay; else AUR=paru; fi

    aur=( $(list "$DOTS/packages/aur.txt") )
    (( STEAM )) && aur+=( $(list "$DOTS/packages/steam-aur.txt") )
    (( TABLET )) && aur+=( $(list "$DOTS/packages/tablet-aur.txt") )
    (( ${#aur[@]} )) && run "$AUR" -S --needed --noconfirm "${aur[@]}"
fi

# ─────────────────────────── ссылки на конфиги
bold "Конфиги → ссылки на $DOTS/home"

link() {
    local src="$1" dst="$2"
    if [[ -L "$dst" && "$(readlink -f "$dst")" == "$(readlink -f "$src")" ]]; then
        info "уже на месте: ${dst/#$HOME/~}"
        return
    fi
    if [[ -e "$dst" || -L "$dst" ]]; then
        # файлы, которые шелл уже сгенерировал под вашу тему и мониторы (есть в defaults/),
        # переносим в ~/my-dotfiles — иначе их заменят начальные версии
        if [[ -d "$dst" && ! -L "$dst" && -d "$src" ]]; then
            local rel="${dst#$HOME/}" f
            while IFS= read -r -d '' f; do
                f="${f#$DOTS/defaults/$rel/}"
                if [[ -f "$dst/$f" && ! -e "$src/$f" ]]; then
                    run cp -p "$dst/$f" "$src/$f"
                    info "сохранён свой ${rel}/$f"
                fi
            done < <(find "$DOTS/defaults/$rel" -type f -print0 2>/dev/null)
        fi
        run mkdir -p "$BACKUP/$(dirname "${dst#$HOME/}")"
        run mv "$dst" "$BACKUP/${dst#$HOME/}"
        info "старое → ${BACKUP/#$HOME/~}/${dst#$HOME/}"
    fi
    run mkdir -p "$(dirname "$dst")"
    run ln -s "$src" "$dst"
    info "${dst/#$HOME/~} → ${src/#$DOTS/dots}"
}

link "$DOTS/home/.zshrc" "$HOME/.zshrc"
for d in quickshell niri foot nvim yazi; do
    link "$DOTS/home/.config/$d" "$HOME/.config/$d"
done
for f in "$DOTS"/home/.local/bin/*; do
    link "$f" "$HOME/.local/bin/$(basename "$f")"
done

# файлы, которые шелл генерирует под тему: начальные версии, если их ещё нет
bold "Начальные файлы темы"
while IFS= read -r -d '' f; do
    rel="${f#$DOTS/defaults/}"
    dst="$HOME/$rel"
    if [[ ! -e "$dst" ]]; then
        run mkdir -p "$(dirname "$dst")"
        run cp "$f" "$dst"
        info "создан ~/$rel"
    fi
done < <(find "$DOTS/defaults" -type f -print0)

# ─────────────────────────── настройки шелла (тема, бар, виджеты, закреплённые)
# Quickshell хранит их в ~/.local/state/quickshell/by-shell/<md5 пути к shell.qml>/.
# Путь бывает и через ссылку, и настоящий — кладём в оба места, если там пусто.
bold "Настройки шелла"
for p in "$HOME/.config/quickshell/shell.qml" "$(readlink -f "$HOME/.config/quickshell")/shell.qml"; do
    id=$(printf '%s' "$p" | md5sum | cut -c1-32)
    dir="$HOME/.local/state/quickshell/by-shell/$id"
    for f in "$DOTS"/state/quickshell/*.json; do
        [[ -e "$dir/$(basename "$f")" ]] && continue
        run mkdir -p "$dir"
        run cp "$f" "$dir/"
        info "$(basename "$f") → ${dir/#$HOME/~}"
    done
done

# ─────────────────────────── Steam: тема для Millennium
if (( STEAM )); then
    bold "Steam: тема «Rexilone»"
    if pgrep -x steam >/dev/null; then
        info "Steam запущен — закройте его и выполните: ~/.config/quickshell/steam-theme/install.sh"
    else
        run "$HOME/.config/quickshell/steam-theme/install.sh" || info "Запустите Steam один раз, закройте и повторите steam-theme/install.sh"
    fi
fi

# ─────────────────────────── планшет
if (( TABLET )); then
    bold "OpenTabletDriver"
    run systemctl --user enable --now opentabletdriver.service || true
    info "модули wacom/hid_uclogic отключатся после перезагрузки (так задумано драйвером)"
fi

# ─────────────────────────── службы и оболочка
bold "Службы"
if (( PACKAGES )); then
    run sudo systemctl enable --now bluetooth.service || true
    (( PRINTERS )) && { run sudo systemctl enable --now cups.service || true; }

    # экран входа: LightDM с GTK-greeter, по умолчанию — сессия niri.
    # Без него система грузится в tty и просит логин/пароль текстом.
    if [[ -f /usr/share/xgreeters/lightdm-gtk-greeter.desktop ]]; then
        info "Экран входа: LightDM → niri"
        conf=$'[Seat:*]\ngreeter-session=lightdm-gtk-greeter\nuser-session=niri\n'
        if (( DRY )); then
            printf '  [dry-run] /etc/lightdm/lightdm.conf.d/50-rexilone.conf:\n%s' "$conf"
        else
            sudo install -d /etc/lightdm/lightdm.conf.d
            printf '%s' "$conf" | sudo tee /etc/lightdm/lightdm.conf.d/50-rexilone.conf >/dev/null
        fi
        # -f заменяет другой экран входа (gdm, sddm, ly…), если он был включён
        run sudo systemctl enable -f lightdm.service
        run sudo systemctl set-default graphical.target
    fi
fi
# Chromium — браузер по умолчанию (ссылки из приложений, Super+B)
if command -v chromium >/dev/null && [[ "$(xdg-settings get default-web-browser 2>/dev/null)" != chromium.desktop ]]; then
    info "Chromium — браузер по умолчанию"
    run xdg-settings set default-web-browser chromium.desktop
fi
if [[ "$(getent passwd "$USER" | cut -d: -f7)" != */zsh ]]; then
    info "Делаю zsh оболочкой по умолчанию"
    run chsh -s /usr/bin/zsh
fi

bold "Готово"
cat <<EOF
  Перезагрузитесь: появится экран входа (LightDM), введите пароль — запустится niri.
  Бар запускается сам (spawn-at-startup "qs" в ~/.config/niri/config.kdl).
  Super+D — приложения, Super+I — настройки, Super+Shift+E — питание.
EOF
[[ -d "$BACKUP" ]] && echo "  Прежние файлы: ${BACKUP/#$HOME/~}"
exit 0
