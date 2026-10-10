<div align="center">

# Rexilone Shell

**A minimal desktop on [niri](https://github.com/YaLTeR/niri) + [Quickshell](https://quickshell.org)**

Bar, menus, settings app, launcher, notifications, widgets and a screen recorder —
one color scheme across the shell, terminal, Neovim, yazi, GTK apps and even Steam.

[Русский](README.ru.md) · [Install](#install) · [Features](#features) · [Phone](#phone-rexlink) · [Updates](#updates)

![Desktop](docs/desktop.png)

</div>

## Screenshots

| | |
|---|---|
| ![Settings](docs/settings.png) | ![Calendar](docs/calendar.png) |
| **Settings** — minimal and clean, every option in one place | **Clock menu** — calendar with notes and reminders, player, weather, system |
| ![Screen recorder](docs/screen-recorder.png) | ![Power menu](docs/power-menu.png) |
| **Screen recorder** — monitor, region or window, system audio and mic, instant replay | **Power menu** — lock, suspend, logout, reboot, shutdown |

![System stats](docs/system-stats.png)

## Features

- **Bar** — workspaces, clock, weather, tray (inline or in a menu), keyboard layout, volume and mic mixers, network, notifications, control center. Flat, floating or pill style; any monitor.
- **Settings app** (`Super+I`) — display arrangement, sound, network & firewall, Bluetooth, phone, peripherals (keyboard, mouse, touchpad, graphics tablet, gamepads, printers), personalization, keyboard shortcuts, startup apps, power, notifications, updates. English and Russian.
- **Color schemes** — dark, light, Nord, Gruvbox, Rosé Pine or generated from the wallpaper; applied live to foot, Neovim, yazi, fzf, GTK and Qt apps.
- **Boot & login** — the Limine boot menu and the LightDM login screen in the shell's colors and wallpaper; Windows and other Linux on any connected disk show up in the boot menu by themselves (Settings → Boot & login).
- **Voice typing** (`Super+H`) — Voxtype with a multilingual Whisper model: press, speak Russian or English, press again — the text is typed where the cursor is.
- **On-screen indicator** — slides up from the bottom when volume, microphone or brightness change and while voice typing listens.
- **Software** — install apps from pacman and AUR: categories, editors' picks, screenshots, search across repositories and AUR, one-click install, remove and update (password via the polkit dialog). Opens from the launcher.
- **Launcher** (`Super+D`) — fuzzy search (also in the wrong keyboard layout), pinned apps, calculator, `>` shell commands, `?` web search, app actions, settings pages.
- **Notifications** with history and Do not disturb; **clipboard history** with images (`Super+V`).
- **Screen recorder** (`Alt+Z`) on gpu-screen-recorder; **hide a window from screencasts** (`Super+G`).
- **Desktop widgets** — clock, system rings, weather, media, calendar, notes, quotes, phone.
- **Wallpaper switcher** (`Super+W`), **polkit** password dialog, **power menu** (`Super+Shift+E`).
- **Steam theme** for [Millennium](https://steambrew.app) that follows the shell's colors.
- **Graphics tablet** area, screen and rotation through OpenTabletDriver.
- **Phone** — Rexlink is built in: notifications, SMS, calls, files, shared clipboard, webcam and the device screen, all in **Settings → Phone**. See [below](#phone-rexlink).
- **Plugins** — write your own bar modules and settings pages (see `home/.config/quickshell/plugins/README.md`).

## Install

### Arch Linux

```sh
git clone https://github.com/Rexilone/my-dotfiles ~/my-dotfiles
cd ~/my-dotfiles
./install.sh --all        # everything: Steam theme, OpenTabletDriver, printers, phone webcam
```

Or pick what you need:

```sh
./install.sh                              # base system
./install.sh --with-steam --with-tablet   # + Steam theme, + graphics tablet
./install.sh --with-webcam                # + phone as a webcam (v4l2loopback)
./install.sh --link-only                  # configs only, no packages
./install.sh --dry-run                    # show what would happen
```

The installer:

1. installs packages from `packages/*.txt` (pacman + AUR via paru, installs paru if needed);
2. **links** the configs to this folder — edit `~/my-dotfiles` and it's live; whatever was there is moved to `~/.dots-backup/<date>/`;
3. puts default theme files from `defaults/` (the shell regenerates them for your scheme);
4. applies the settings preset from `state/` (scheme, bar, modules);
5. sets up the Rexlink service (phone link) and opens its ports in ufw;
6. optionally sets up the Steam theme, OpenTabletDriver, CUPS and the phone webcam;
7. sets up the login screen (LightDM, niri session by default), makes zsh the login shell and enables Bluetooth.

Then reboot, enter your password on the login screen — niri and the bar start by themselves.

### NixOS

A flake with a system module and a Home Manager module is in [`nixos/`](nixos/README.md).

## Phone (Rexlink)

Android phones, tablets and watches connect to the desktop over the local network. Rexlink is part of the system: a background service (`rexlink.service`) with no window of its own — everything is in **Settings → Phone**, the bar, the desktop widget and the incoming call card.

| | |
|---|---|
| **Notifications** | from every device, as regular pop-ups with actions and quick reply; dismissing syncs both ways |
| **Messages** | SMS conversations, replies, new messages |
| **Calls** | incoming call card with Answer / Decline, dialing from the PC |
| **Files** | drag files onto the page or pick them; Share → Rexlink on the phone; progress and cancel |
| **Clipboard** | text and images both ways |
| **Webcam** | the phone camera as a regular webcam (`--with-webcam`) |
| **Device screen** | see and control the screen with mouse and keyboard; can keep working with the device screen off (ADB) |
| **Media** | the phone's player on the PC and the PC's player on the phone |

Install `rexlink/rexlink.apk` on the device, open it, pick the computer and check the six-digit code. Everything goes over TLS; ports — TCP 47820 and UDP 47821. Details and the API for scripts: [`rexlink/README.md`](rexlink/README.md).

## Updates

**Settings → Updates** checks this repository for new commits (automatically, a minute after login and every 6 hours), shows what's new and updates with one click: `git pull`, new links, shell restart. If the package lists changed, it offers to install the new packages. Local changes in `~/my-dotfiles` are never overwritten — commit or stash them first.

The same page shows pacman updates.

## Keybindings

| Keys | Action |
|------|--------|
| `Super+D` | Launcher |
| `Super+I` | Settings |
| `Super+V` | Clipboard history |
| `Super+W` | Wallpapers |
| `Super+G` | Hide the window from screencasts |
| `Alt+Z` | Screen recorder |
| `Super+Shift+E` | Power menu |
| `Super+T` | Terminal (foot) |
| `Super+B` | Browser (Chromium) |
| `Super+H` | Voice typing (Russian / English) |
| `Super+Shift+wheel` | Magnifier: zoom in / out (screen snapshot) |

All shortcuts can be changed in **Settings → Keyboard shortcuts**.

## Layout

| Path | What |
|------|------|
| `home/.config/quickshell/` | the shell: bar, menus, settings, services, plugins, Steam theme |
| `home/.config/niri/` | niri: keybindings, window rules, autostart |
| `home/.config/{foot,nvim,yazi}/` | terminal, editor, file manager |
| `home/.zshrc`, `home/.local/bin/` | zsh and helper scripts |
| `home/.config/quickshell/scripts/store.py` | Software (app installer) data: catalog, search, package info, updates |
| `boot/` | rexilone-boot: boot menu and login screen theme, systems on other disks (root service, udev rule) |
| `rexlink/` | Rexlink service (phone link), the Android app and its system files |
| `defaults/` | initial versions of files the shell generates for the color scheme |
| `state/quickshell/` | settings preset applied on install |
| `packages/` | package lists for Arch |
| `nixos/` | NixOS flake |
| `docs/` | screenshots |

## License

[MIT](LICENSE)

## Credits

[niri](https://github.com/YaLTeR/niri) · [Quickshell](https://quickshell.org) · [foot](https://codeberg.org/dnkl/foot) · [yazi](https://github.com/sxyazi/yazi) · [Neovim](https://neovim.io) · [Millennium](https://steambrew.app) · [OpenTabletDriver](https://opentabletdriver.net) · [gpu-screen-recorder](https://git.dec05eba.com/gpu-screen-recorder) · [JetBrains Mono Nerd Font](https://www.nerdfonts.com)
