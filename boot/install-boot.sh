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
echo "rexilone-boot установлен"
