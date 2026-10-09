{
  description = "Rexilone: niri + Quickshell — рабочее окружение для NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Steam с Millennium (тема «Rexilone» для клиента Steam)
    millennium.url = "github:SteamClientHomebrew/Millennium?dir=packages/nix";
  };

  outputs = { nixpkgs, home-manager, millennium, ... }:
    let
      # ── поменяйте под себя
      user = "rexilone";
      hostname = "rexilone";
      dots = "/home/${user}/my-dotfiles";   # где лежит этот репозиторий
    in
    {
      # модули — чтобы подключить окружение к своей существующей конфигурации
      nixosModules.rexilone = import ./modules/system.nix;
      homeModules.rexilone = import ./modules/home.nix;

      # готовая система: nixos-rebuild switch --flake ~/my-dotfiles/nixos#rexilone
      nixosConfigurations.${hostname} = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit user dots millennium; };
        modules = [
          ./hosts/rexilone/configuration.nix
          ./modules/system.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "before-dots";
            home-manager.extraSpecialArgs = { inherit user dots; };
            home-manager.users.${user} = import ./modules/home.nix;
          }
        ];
      };
    };
}
