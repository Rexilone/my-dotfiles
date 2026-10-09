# Системная часть: композитор, оболочка, звук, Bluetooth, шрифты, порталы.
# Необязательное включается в hosts/<имя>/configuration.nix:
#   rexilone.steam.enable / rexilone.tablet.enable / rexilone.printers.enable
{ config, lib, pkgs, user, millennium, ... }:

let
  cfg = config.rexilone;
in
{
  options.rexilone = {
    steam.enable = lib.mkEnableOption "Steam с Millennium и темой «Rexilone»";
    tablet.enable = lib.mkEnableOption "OpenTabletDriver (рабочая область, поворот, кнопки пера)";
    printers.enable = lib.mkEnableOption "печать и сканирование (CUPS, SANE)";
  };

  config = lib.mkMerge [
    {
      # ── композитор и оболочка
      programs.niri.enable = true;
      programs.xwayland.enable = true;
      xdg.portal = {
        enable = true;
        extraPortals = [ pkgs.xdg-desktop-portal-gnome pkgs.xdg-desktop-portal-gtk ];
      };

      # ── пользователь и zsh
      programs.zsh.enable = true;
      users.users.${user} = {
        isNormalUser = true;
        shell = pkgs.zsh;
        extraGroups = [ "wheel" "video" "render" "networkmanager" ];
      };

      # ── службы, которые нужны меню бара
      security.polkit.enable = true;
      security.pam.services.swaylock = { };       # блокировка экрана
      services.upower.enable = true;              # заряд беспроводных устройств
      services.gvfs.enable = true;                # телефон и флешки в yazi
      services.udisks2.enable = true;
      hardware.bluetooth.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        pulse.enable = true;
        jack.enable = true;
      };
      programs.gpu-screen-recorder.enable = true; # запись экрана (Alt+Z)

      environment.systemPackages = with pkgs; [
        quickshell
        xwayland-satellite
        libnotify
        swaylock

        # терминал и консоль
        foot
        neovim
        tree-sitter
        yazi
        fzf
        fd
        ripgrep
        eza
        bat
        zoxide
        jq
        p7zip
        unzip
        fastfetch
        git
        python3
        zsh-autosuggestions
        zsh-syntax-highlighting
        zsh-completions

        # превью в yazi и перетаскивание файлов
        chafa
        ffmpegthumbnailer
        ueberzugpp
        imagemagick
        ripdrag

        # буфер обмена, обои, запись
        wl-clipboard
        cliphist
        awww                 # обои (в старых nixpkgs пакет назывался swww)
        gpu-screen-recorder

        # браузер (Super+B)
        chromium

        # звук
        pavucontrol
        pulseaudio           # pactl для микшера
      ];

      fonts.packages = with pkgs; [
        nerd-fonts.jetbrains-mono
        jetbrains-mono
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
      ];
    }

    # ── Steam с Millennium
    (lib.mkIf cfg.steam.enable {
      nixpkgs.overlays = [ millennium.overlays.default ];
      programs.steam = {
        enable = true;
        package = pkgs.millennium-steam;
      };
    })

    # ── графический планшет
    (lib.mkIf cfg.tablet.enable {
      hardware.opentabletdriver = {
        enable = true;
        daemon.enable = true;
      };
    })

    # ── принтеры и сканеры
    (lib.mkIf cfg.printers.enable {
      services.printing.enable = true;
      hardware.sane.enable = true;
      environment.systemPackages = [ pkgs.system-config-printer ];
      users.users.${user}.extraGroups = [ "scanner" "lp" ];
    })
  ];
}
