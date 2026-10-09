<div align="center">

# Rexilone Shell

**A minimal desktop on [niri](https://github.com/YaLTeR/niri) + [Quickshell](https://quickshell.org)**

Bar, menus, settings app, launcher, notifications, widgets and a screen recorder —
one color scheme across the shell, terminal, Neovim, yazi, GTK apps and even Steam.

[Русский](README.ru.md) · [Install](#install) · [Features](#features) · [Updates](#updates)

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
- **Settings app** (`Super+I`) — display arrangement, sound, network & firewall, Bluetooth, peripherals (keyboard, mouse, touchpad, graphics tablet, gamepads, printers), personalization, keyboard shortcuts, startup apps, power, notifications, updates. English and Russian.
- **Color schemes** — dark, light, Nord, Gruvbox, Rosé Pine or generated from the wallpaper; applied live to foot, Neovim, yazi, fzf, GTK and Qt apps.
- **Launcher** (`Super+D`) — fuzzy search (also in the wrong keyboard layout), pinned apps, calculator, `>` shell commands, `?` web search, app actions, settings pages.
- **Notifications** with history and Do not disturb; **clipboard history** with images (`Super+V`).
- **Screen recorder** (`Alt+Z`) on gpu-screen-recorder; **hide a window from screencasts** (`Super+G`).
- **Desktop widgets** — clock, system rings, weather, media, calendar, notes, quotes, phone.
- **Wallpaper switcher** (`Super+W`), **polkit** password dialog, **power menu** (`Super+Shift+E`).
- **Steam theme** for [Millennium](https://steambrew.app) that follows the shell's colors.
- **Graphics tablet** area, screen and rotation through OpenTabletDriver.
- **Phone integration** through Rexlink (optional).
- **Plugins** — write your own bar modules and settings pages (see `home/.config/quickshell/plugins/README.md`).

## Install

### Arch Linux

```sh
git clone https://github.com/Rexilone/my-dotfiles ~/my-dotfiles
cd ~/my-dotfiles
./install.sh --all        # everything: Steam theme, OpenTabletDriver, printers
```

Or pick what you need:

```sh
./install.sh                              # base system
./install.sh --with-steam --with-tablet   # + Steam theme, + graphics tablet
./install.sh --link-only                  # configs only, no packages
./install.sh --dry-run                    # show what would happen
```

The installer:

1. installs packages from `packages/*.txt` (pacman + AUR via paru, installs paru if needed);
2. **links** the configs to this folder — edit `~/my-dotfiles` and it's live; whatever was there is moved to `~/.dots-backup/<date>/`;
3. puts default theme files from `defaults/` (the shell regenerates them for your scheme);
4. applies the settings preset from `state/` (scheme, bar, modules);
5. optionally sets up the Steam theme, OpenTabletDriver and CUPS;
6. sets up the login screen (LightDM, niri session by default), makes zsh the login shell and enables Bluetooth.

Then reboot, enter your password on the login screen — niri and the bar start by themselves.

### NixOS

A flake with a system module and a Home Manager module is in [`nixos/`](nixos/README.md).

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

All shortcuts can be changed in **Settings → Keyboard shortcuts**.

## Layout

| Path | What |
|------|------|
| `home/.config/quickshell/` | the shell: bar, menus, settings, services, plugins, Steam theme |
| `home/.config/niri/` | niri: keybindings, window rules, autostart |
| `home/.config/{foot,nvim,yazi}/` | terminal, editor, file manager |
| `home/.zshrc`, `home/.local/bin/` | zsh and helper scripts |
| `defaults/` | initial versions of files the shell generates for the color scheme |
| `state/quickshell/` | settings preset applied on install |
| `packages/` | package lists for Arch |
| `nixos/` | NixOS flake |
| `docs/` | screenshots |

## License

[MIT](LICENSE)

## Credits

[niri](https://github.com/YaLTeR/niri) · [Quickshell](https://quickshell.org) · [foot](https://codeberg.org/dnkl/foot) · [yazi](https://github.com/sxyazi/yazi) · [Neovim](https://neovim.io) · [Millennium](https://steambrew.app) · [OpenTabletDriver](https://opentabletdriver.net) · [gpu-screen-recorder](https://git.dec05eba.com/gpu-screen-recorder) · [JetBrains Mono Nerd Font](https://www.nerdfonts.com)
