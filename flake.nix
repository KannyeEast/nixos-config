{
    description = "Very cool NixOS config";

    inputs = {
        #
        # Nix architecture
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
        };
        
        ### Home-manager
        home-manager = {
            url = "github:nix-community/home-manager";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        
        ## Secrets        
        sops-nix = {
            url = "github:Mic92/sops-nix";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        
        #
        # Dendritic Pattern
        #
         
        ## Flake modules
        flake-parts = {
            url = "github:hercules-ci/flake-parts";
            inputs.nixpkgs-lib.follows = "nixpkgs";    
        };
        
        ## Import modules recursively 
        import-tree.url = "github:denful/import-tree";
         
        #
        # Profiles
        #
        
        # Server
        ## Infrastructure and network diagrams
        nix-topology = {
            url = "github:oddlama/nix-topology";
            inputs.nixpkgs.follows = "nixpkgs";
            inputs.flake-parts.follow = "flake-parts";
        };
        
        # Workstation        
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