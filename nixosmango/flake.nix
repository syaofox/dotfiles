{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    mangowc = {
      url = "github:DreamMaoMao/mangowc";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, mangowc, home-manager, ... }: {
    nixosConfigurations.mango = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        mangowc.nixosModules.default  
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            users.mango = import ./home.nix;
            backupFileExtension = "backup";
          };
        }
      ];
    };
  };
}