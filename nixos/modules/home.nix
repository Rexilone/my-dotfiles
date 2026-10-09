# Пользовательская часть (Home Manager): конфиги — ссылками на ~/my-dotfiles, как на Arch.
# Ссылки «вне store» (mkOutOfStoreSymlink): шелл пишет в эти папки (тема терминала,
# nvim, yazi, Steam), а правки в ~/my-dotfiles работают без пересборки.
{ config, lib, pkgs, user, dots, ... }:

let
  link = path: config.lib.file.mkOutOfStoreSymlink "${dots}/home/${path}";
in
{
  home.username = user;
  home.homeDirectory = "/home/${user}";
  home.stateVersion = "25.05";

  home.file = {
    ".zshrc".source = link ".zshrc";
    ".local/bin/niri-cast-toggle".source = link ".local/bin/niri-cast-toggle";
    ".local/bin/ripdrag-drop".source = link ".local/bin/ripdrag-drop";
    # тема Steam (Millennium) — нужна, если включён rexilone.steam
    ".local/share/Steam/millennium/themes/rexilone".source = link ".config/quickshell/steam-theme";
  };

  xdg.configFile = {
    "quickshell".source = link ".config/quickshell";
    "niri".source = link ".config/niri";
    "foot".source = link ".config/foot";
    "nvim".source = link ".config/nvim";
    "yazi".source = link ".config/yazi";
  };

  # начальные файлы темы (их потом переписывает шелл) и настройки шелла — только если их ещё нет
  home.activation.rexiloneDefaults = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    cd ${dots}/defaults
    find . -type f | while read -r f; do
      dst="$HOME/''${f#./}"
      if [ ! -e "$dst" ]; then
        mkdir -p "$(dirname "$dst")"
        cp "$f" "$dst"
      fi
    done

    for p in "$HOME/.config/quickshell/shell.qml" "${dots}/home/.config/quickshell/shell.qml"; do
      id=$(printf '%s' "$p" | ${pkgs.coreutils}/bin/md5sum | cut -c1-32)
      dir="$HOME/.local/state/quickshell/by-shell/$id"
      mkdir -p "$dir"
      for f in ${dots}/state/quickshell/*.json; do
        [ -e "$dir/$(basename "$f")" ] || cp "$f" "$dir/"
      done
    done
  '';
}
