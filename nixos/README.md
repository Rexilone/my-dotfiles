# NixOS

Окружение для NixOS: flake с системным модулем и модулем Home Manager.
Конфиги — те же файлы из `~/my-dotfiles/home`, подключённые ссылками.

## Установка

```sh
git clone https://github.com/Rexilone/my-dotfiles ~/my-dotfiles
cd ~/my-dotfiles/nixos

# своё железо
sudo nixos-generate-config --show-hardware-config > hosts/rexilone/hardware-configuration.nix

# имя пользователя, хоста и путь к ~/my-dotfiles — в начале flake.nix
# что включить (Steam, планшет, принтеры), загрузчик, часовой пояс — hosts/rexilone/configuration.nix

sudo nixos-rebuild switch --flake .#rexilone
```

После перезагрузки войдите в niri (greetd → tuigreet). Бар запустится сам.

## Модули по отдельности

К своей конфигурации можно подключить только модули:

```nix
imports = [ inputs.rexilone.nixosModules.rexilone ];
home-manager.users.<вы> = inputs.rexilone.homeModules.rexilone;
```

Модулям нужны аргументы `user`, `dots` (и `millennium` — для Steam) через `specialArgs` / `extraSpecialArgs`, как в `flake.nix`.

## Что отличается от Arch

- **Брандмауэр**: на NixOS это `networking.firewall`, а страница «Сеть → Брандмауэр» в Настройках работает с `ufw` — её на NixOS лучше не трогать.
- **Обновления системы** в баре считаются через pacman — на NixOS модуль «Обновления» не нужен.
- **Steam**: `millennium-steam` из flake Millennium; тему выбирать не нужно, ссылка на неё ставится Home Manager.
