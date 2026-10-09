# Системная часть: композитор, оболочка, звук, Bluetooth, шрифты, порталы.
# Необязательное включается в hosts/<имя>/configuration.nix:
#   rexilone.steam.enable / rexilone.tablet.enable / rexilone.printers.enable / rexilone.webcam.enable
{ config, lib, pkgs, user, dots, millennium, ... }:

let
  cfg = config.rexilone;
  # Rexlink: служба связи с телефоном (код — ${dots}/rexlink), Python с PySide6
  rexlinkPython = pkgs.python3.withPackages (p: [ p.pyside6 ]);
in
{
  options.rexilone = {
    steam.enable = lib.mkEnableOption "Steam с Millennium и темой «Rexilone»";
    tablet.enable = lib.mkEnableOption "OpenTabletDriver (рабочая область, поворот, кнопки пера)";
    printers.enable = lib.mkEnableOption "печать и сканирование (CUPS, SANE)";
    webcam.enable = lib.mkEnableOption "телефон как веб-камера (v4l2loopback для Rexlink)";
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

      # ── Rexlink: связь с телефоном (Настройки → Телефон). TCP 47820 — связь, UDP 47821 — поиск
      networking.firewall.allowedTCPPorts = [ 47820 ];
      networking.firewall.allowedUDPPorts = [ 47821 ];
      systemd.user.services.rexlink = {
        description = "Rexlink — связь с телефоном (служба шелла)";
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
        path = with pkgs; [ ffmpeg wl-clipboard playerctl openssl glib iproute2 xdg-utils android-tools scrcpy quickshell systemd ];
        environment.REXLINK_PYTHON = "${rexlinkPython}/bin/python3";
        serviceConfig = {
          ExecStart = "${dots}/home/.local/bin/rexlink";
          Restart = "on-failure";
          RestartSec = 3;
        };
      };

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

        # Rexlink (экран устройства без запроса, режим «экран выключен»)
        android-tools
        scrcpy
        playerctl

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

    # ── веб-камера из телефона: /dev/video42 «Rexlink Camera»
    (lib.mkIf cfg.webcam.enable {
      boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
      boot.kernelModules = [ "v4l2loopback" ];
      boot.extraModprobeConfig = ''
        options v4l2loopback devices=1 video_nr=42 exclusive_caps=1 card_label="Rexlink Camera"
      '';
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
