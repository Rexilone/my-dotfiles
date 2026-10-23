#!/bin/sh
# Установка системной части «Загрузка и вход» (root): install-boot.sh <папка дотфайлов> <пользователь>
# Вызывают install.sh и Настройки → Загрузка и вход (через pkexec).
set -eu
dots=${1:?папка дотфайлов}
user=${2:?пользователь}
[ "$(id -u)" -eq 0 ] || { echo "нужен root" >&2; exit 1; }
id "$user" >/dev/null 2>&1 || { echo "нет пользователя $user" >&2; exit 1; }

install -Dm755 "$dots/boot/rexilone-boot" /usr/local/lib/rexilone/rexilone-boot
install -Dm644 "$dots/boot/rexilone-boot.service" /etc/systemd/system/rexilone-boot.service
install -Dm644 "$dots/boot/rexilone-boot-scan.service" /etc/systemd/system/rexilone-boot-scan.service
install -Dm644 "$dots/boot/90-rexilone-boot.rules" /etc/udev/rules.d/90-rexilone-boot.rules
# экран входа RexOS (greetd → niri → Quickshell): программа — общая, тема — в /var/lib/rexilone/greeter
# greetd — из репозитория Arch, если ещё не стоит (обновление из Настроек ставит пакеты не всегда)
if command -v pacman >/dev/null && ! pacman -T greetd greetd-agreety >/dev/null 2>&1; then
    pacman -S --needed --noconfirm greetd greetd-agreety || echo "не удалось поставить greetd" >&2
fi
install -Dm755 "$dots/boot/rexilone-greeter" /usr/local/lib/rexilone/rexilone-greeter
rm -rf /usr/local/share/rexilone/greeter
install -d /usr/local/share/rexilone
cp -r "$dots/boot/greeter" /usr/local/share/rexilone/greeter
chown -R root:root /usr/local/share/rexilone/greeter
chmod -R u=rwX,go=rX /usr/local/share/rexilone/greeter
# куда экран входа может писать (последний пользователь, счётчик сбоев, кеш Quickshell)
if id greeter >/dev/null 2>&1; then
    install -d -m 755 /var/lib/rexilone
    install -d -o greeter -g greeter -m 700 /var/lib/rexilone/greeter-state
fi
# «найти курсор встряхиванием» больше нет — убрать, если ставился раньше
if [ -f /etc/systemd/system/rexilone-shake.service ]; then
    systemctl disable --now rexilone-shake.service >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/rexilone-shake.service /usr/local/lib/rexilone/rexilone-shake
    rm -rf /run/rexilone
fi
install -d /etc/rexilone
printf 'user=%s\n' "$user" > /etc/rexilone/boot.conf

systemctl daemon-reload
udevadm control --reload || true
systemctl enable rexilone-boot.service >/dev/null 2>&1
# применить сразу (поиск систем + оформление)
systemctl restart rexilone-boot.service
# экран входа RexOS — по умолчанию; если в Настройках выбрали другой (/etc/rexilone/dm), не трогаем
if [ ! -f /etc/rexilone/dm ] && [ -x /usr/bin/greetd ]; then
    /usr/local/lib/rexilone/rexilone-boot dm rexilone || true
fi
echo "rexilone-boot установлен"
