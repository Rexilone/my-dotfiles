# Машина. Сгенерируйте hardware-configuration.nix на месте:
#   sudo nixos-generate-config --show-hardware-config > ~/my-dotfiles/nixos/hosts/rexilone/hardware-configuration.nix
{ pkgs, user, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # ── что включить из окружения
  rexilone.steam.enable = true;
  rexilone.tablet.enable = true;
  rexilone.printers.enable = false;
  rexilone.webcam.enable = false;    # телефон как веб-камера (Rexlink)

  # ── загрузка и система (поправьте под себя)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "rexilone";
  networking.networkmanager.enable = true;

  time.timeZone = "UTC";              # ваш часовой пояс, например "Europe/Moscow"
  i18n.defaultLocale = "en_US.UTF-8";

  # вход: tuigreet запускает niri
  services.greetd = {
    enable = true;
    settings.default_session.command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd niri-session";
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;   # Steam

  system.stateVersion = "25.05";
}
