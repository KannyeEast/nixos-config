{
  description = "Very cool NixOS config";

  inputs = {
    #
    # Config architecture
    #

    ## Unstable packages
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    ## Hardware tweaks
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ## Disk partitioning
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ## Declarative/Opt-in persistence
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    ## Home-manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ## Secrets
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ## Flake modules
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    ## Import modules recursively
    import-tree.url = "github:denful/import-tree";

    #
    # Classes
    #

    # Desktop
    ## Shell
    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ## Browser
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    
    ## Shell
    # @TODO: Custom shell import here

    # Server
    ## Infrastructure and network diagrams
    nix-topology = {
      url = "github:oddlama/nix-topology";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };

    #
    # Addons
    #

    # Dev
    ## Jetbrains
    nix-jetbrains-plugins = {
      url = "github:nix-community/nix-jetbrains-plugins";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ## Undo
    undo = {
      url = "github:edaywalid/undo";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    let
      hostData = import ./lib/validHosts.nix;

      systems = inputs.nixpkgs.lib.unique (map (data: data.host.system) (builtins.attrValues hostData));
    in
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.flake-parts.flakeModules.modules
        (inputs.import-tree ./modules)
      ]
      ++ map (import ./lib/mkHost.nix) (builtins.attrNames hostData);

      # perSystem outputs (devShell, formatter) exist for every architecture there is a host of
      # derived from hosts/<host>/host.json -> host.system
      inherit systems;

      perSystem =
        { pkgs, ... }:
        {
          formatter = pkgs.nixfmt;

          devShells.default = pkgs.mkShell {
            packages = [
              pkgs.deadnix
              pkgs.just
              pkgs.nixfmt
            ];
          };
        };
    };
}
