{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mango = {
      url = "github:DreamMaoMao/mango";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, mango, home-manager, ... }: {
    nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        home-manager.nixosModules.home-manager
        mango.nixosModules.mango
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            users.syaofox = {
              imports = [
                ./home.nix
                mango.hmModules.mango
              ];
            };
            backupFileExtension = "backup";
          };
        }
      ];
    };
  };
}