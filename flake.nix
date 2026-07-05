{
    description = "Very cool NixOS config";

    inputs = {
        # Core
        ## Unstable packages
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";        
        
        ## Flake modules
        flake-parts = {
            url = "github:hercules-ci/flake-parts";
            inputs.nixpkgs-lib.follows = "nixpkgs";    
        };
        
        ## Import modules recursively 
        import-tree.url = "github:denful/import-tree";
        
        ## Disk partitioning 
        disko = {
            url = "github:nix-community/disko";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        
        ## Declarative/Opt-in persistence 
        impermanence = {
            url = "github:nix-community/impermanence";
            inputs.nixpkgs.follows = "nixpkgs"; 
        };
        
        ## Wrapper
        wrapper-modules = {
            url = "github:BirdeeHub/nix-wrapper-modules";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        
        ## Secrets
        agenix = {
            url = "github:ryantm/agenix";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        
#        sops-nix = {
#            url = "github:Mic92/sops-nix";
#            inputs.nixpkgs.follows = "nixpkgs";
#        };
        
        # Profiles
        ## Server

        
        ## Workstation
        ### Home-manager
        home-manager = {
            url = "github:nix-community/home-manager";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        
        ### Hardware tweaks
        nixos-hardware = {                                          
            url = "github:NixOS/nixos-hardware/master";  
            inputs.nixpkgs.follows = "nixpkgs";
        };
        
        ## Shell
        quickshell = {
            url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
            inputs.nixpkgs.follows = "nixpkgs";
        };

        ### Browser
        zen-browser = {
            url = "github:0xc000022070/zen-browser-flake";
            inputs.nixpkgs.follows = "nixpkgs";
            inputs.home-manager.follows = "home-manager";
        };

        # @TODO: Custom packages
        # >> https://github.com/pewdiepie-archdaemon/odysseus
    };

    outputs = inputs:
        inputs.flake-parts.lib.mkFlake { inherit inputs; } {
            imports = [
                inputs.flake-parts.flakeModules.modules
                (inputs.import-tree [ ./hosts ./modules ])
            ];
        };
}



