## Todos
- Git structure/branches
- We need scripts to automate most commands, so they workd from anywhere (adding to git, cd into dir temporarily, etc.)

***
# **Profiles**

## Workstation
a
## Server
a
***

### File structure

> File names use kebab-case, while variable names use camelCase

> #### Modules
> 
> ``` nix
> <generic-module.nix>
> # Outer = flake-parts module
> { self, inputs, config, lib, ... }:
> let
>     inherit (config.flake.modules) nixos;                                                               # At the top level we only inherit flake-level attributes
>     inherit (lib) mkEnableOption mkOption mkMerge mkIf mkDefault mkForce mkOverride types <helpers>;    # or import lib. attributes to avoid repeated code blocks 
> in
> {
>     # Inner = nixos module
>     flake.modules.nixos.<moduleName> = { config, lib, pkgs, <specialArgs>, ... }:
>     let
>         inherit (config.<foo>) <option>;     # Here we reference the custom user options
>         var = config.<bar>.<option>;         # Alternatively variables can be set in case of a duplicate namespace (but not path) 
>     in
>     {
>         imports = [
>             # Import modules relevant for this module
>             nixos.<module>
>         ];
>
>         options = {
>             # Defining relevant user options
>             <foo>.<option> = mkOption {
>                 type = <type>;
>                 default = <default>;
>                 description = <description>;
>             };
>             <bar>.<option> = mkOption {
>                 type = <type>;
>                 default = <default>;
>                 description = <description>;
>             }; 
>         };
>         
>         config = {
>             # Normal nix file configuration
>         };
>     };
> }
> ```

> #### Hosts
> ``` json
> <host.json>
> {
> "hostname": <hostname>,
> "system": <system>,
> "roles": [ <desktop> <dev> <server> ],
> "user": <username>,
> "hardware": {
>   "platform": <laptop> <desktop>,
>   "gpu": [ <dGPU>, <iGPU> ],
>   "gpuArchitecture": <dGPU Architecture>,
>   "modules": [ <nixos-hardware module(s)> ]
> },
> "locale": {
>   "timeZone": <Timezone>,
>   "localeDefault": <locale>,
>   "localeExtra": <locale>
> },
> "secrets": { "publicKeys": [ "..." ], "ageFiles": [ "..." ] }
> }
> ```
> ``` nix
> <default.nix>
> ```
> ``` nix
> <profile.nix>
> ```
> ``` nix
> <disko.nix>
> ```


## Profile examples

Snippets for the `*.settings` / `*.extras` options. Drop the relevant block
into `hosts/<host>/profile.nix`.

### Bootloader

```nix
bootloader.settings = {
    theme = "${pkgs.sleek-grub-theme}/grub/themes/sleek";
    gfxmodeEfi = "1920x1080";
    configurationLimit = 5;
};
```

### Plymouth
```nix
bootloader.plymouth = {
    theme = "loader_2";
    themePackages = [
        (pkgs.adi1090x-plymouth-themes.override { selected_themes = [ "loader_2" ]; })
    ];
};
# themes: https://github.com/adi1090x/plymouth-themes
```

### Display manager
```nix
settings = {
    theme = "sddm-astronaut-theme";
    extraPackages = with pkgs.kdePackages; [ qtsvg qtmultimedia qtvirtualkeyboard qt5compat ];
};
extraPackages = [ (pkgs.sddm-astronaut.override { embeddedTheme = "astronaut"; }) ];
# themes: https://search.nixos.org/packages?query=sddm+theme
```

### Fonts
```nix
Extend the defaults:        packages = profile.user.fonts.packages ++ [ pkgs.<font> ];
or override entirely:       packages = [ pkgs.<font> ];
```

### Password
```nix

{ config, ... }: 
let 
    inherit (config) profile age;
in

hashedPasswordFile = "/path/to/nixos-secrets/${profile.user.username}";
hashedPasswordFile = age.secrets.<ageFile>.path;
```



# Claude
Rethink the approach - This is my system, so its opinionated. Not endless customization > they can build their own thing and use this as reference
1. Still a host driven config, so multi hosts with multi purpose (and multi user?) is possible
2. Ricing sticks to dotfiles
3. devenv gets declared directly in config (need to figure out what this actually does and what I need/want) >> packaging own binaries to nix
4. Keep configuration potential minimal:
- Only the needed bits are getting build 
- Host determent 
- Opinionated >> The only warrant for options are:
A) Host specific options >> Host A needs X and Y1 but Host B needs Y2 
B) Frequently changing variables regardless of setting (experimental stuff, server settings, etc.)
C) Settings that are more convinient for easy access or are written by the installer (mutliple references, locale settings, etc.) 
- Installer needs to either get/grab info or set it depending on if we use disko or not >> by default we assume a nixos-anywhere install (or however it would work from the installer USB)
- Rethink home/dotfiles approach >> Each host should have their own set of dotfiles (workstation normal ricing, server does docker compose, but can also be both >> both as in its 2 separate file structures and scripts that do their thing) >> No more home directory. Host dependent filse live inside the host
- Restructure _host.nix to be more clear and deliberate (cleaner secrets, move to sops nix) (also understand ssh) >> Maybe convert to JSON? Or yaml? >> This file should carry all of the infrastructure variables (even if they could be evaluated with `config`) and `profile.nix` is just the plain, interchangeable configuration of the system
- Define clear aliases for all common commands, working regardless of the current host (maybe a justfile?) >> Aliases should range from simple QoL shortcuts/visuals, combinations to 'extend' a command (nix rebuild also does git, debug tools, server functions, etc.) to serving programs data it needs (not sure about this but you get what I mean)
- Look at the pipe operator >> https://discourse.nixos.org/t/pre-rfc-pipe-operator/28387 (|> or alternativley lib.pipe)
- Maybe keep structural support even if not needed (?)
- Refactor password approach >> I dont like the plain hardcoded fallbacks >> Also maybe look into how/if I can include the password file for keepassxc in secrets/declarative keepassxc in general
- Create template files ready to be pulled from anywhere via git. Like I see in videos all the time
- Agents.md structure for experimental AI/LLM env (also for setting selfhosting of LLM up)
- setup git branchs (dev and main branch, one with and without personal config) >> When to link git repo to the project?
- Home manager (or just nix?) for setting browser extension settings (dotfiles I guess? Or policies?) >> https://discourse.nixos.org/t/generate-and-install-ublock-config-file-with-home-manager/19209/3 || https://github.com/abhinandh-s/nixdots/blob/master/home/mod/firefox/policies.nix (firefox example, should be roughly same for zen. Maybe also can do some cookie shenanigans + set custom search options and wire shortcut to i.e. directly search nix packages + one could also try to implement some 'features' through scripts I am lacking right now, i.e. open new tab in current container) >> https://github.com/0xc000022070/zen-browser-flake/tree/main/examples
- Enforce consitent dendritic pattern >> One file per (major) setting (can be bundled) https://not-a-number.io/2025/refactoring-my-infrastructure-as-code-configurations/
- Declare as much as possible (keep names generic though so its interchangeable) >> This is true for everything in the config, ideally all settings should either be in the config or a dotfile
- Always allow multi select for options with different programs (i.e. our `flakeModules = [ "home-manager" "secrets" ];`) >> If only one can be true at a time decide on one to implement
- Keep home manager usage minimal (I think, dont really see the benefit yet apart from some exceptions)
- Proper test env >> Both for testing nix configuration, but also for testing an open-source software, extension, or whatever >> Basically QA before it gets included into the system
- This is only for NixOS >> darwin might be worth looking at if I ever get a Mac
- I need windows like screenshot + clipboard history (maybe even selfhost across machines?)
- Need to automatically create diso file with correct settings
- Might also be worth getting the installer script structure up >> I want to break it up into more files, but dont want it to require special permissions
- Not everything needs to be CLI, GUI is sometimes also nice (and vice-versa) >> A mix of both is probably best depending on the softwares
- What about den? >> https://github.com/denful/den (also look at gemini markdown notes) I am currently leaning towards not adding it, but I fear we are just writing a bad version of den
- Write custom tools/functions >> For example a custom version of import-tree
- Need to figure out a clean way to do profiles/roles
- Can one include SimpleLogin in this?

Need to figure out what is hardcoded behind a rebuild (dev) and what is runtime (ricing) (i.e. what is emacs in this case?)

If dualboot then setup refind (This is currently done inside the Win11 EFI)

Priority should be getting a working nix system with dev setup (not the full devenv) so I can iterate directly on nix.
First sort all of this and define a clear toDo list with goals.
Map out these changes and different branches in a similar snapshot way you see in the below examplse: 
- The new filestructure >> the current version and the possible endproduct
- Peeks into file structuree >> Mainly for the non standard/generic nix modules 

https://www.youtube.com/watch?v=2yplBzPCghA
https://github.com/dreamsofautonomy/homelab/blob/main/nixos/configuration.nix

<< This is the main ref for the server | I basically want this (with my set of services) and containers instead of bare metal (so nixos as a hypervisor or is that overkill?) (and no cluster yet)>>
https://www.youtube.com/watch?v=f-x5cB6qCzA (see transcript file)
https://git.notthebe.ee/notthebee/nix-config 
https://www.youtube.com/@WolfgangsChannel (Also just take a look at his channel for general homelabbing stuff)
https://medium.com/@stylishavocado/managing-docker-containers-with-docker-compose-in-nixos-take-2-1153801fb547  >> Needs to be refined
https://lgug2z.com/articles/handling-secrets-in-nixos-an-overview/ >> Secrets

<< Server Notes >>
Focus on getting infrastructure set up. Services can/will come over time.
Understand how to set one up with nixos
Look into clusters instead of singluar node (raspi) (would a cluster be multi host or same host + maybe multi user?)
Lean docker compose (not Kubernetes)
Keep it simple (and small for now), this is not a job >> It should just work
nixos-anywhere
Need a UPS once up and running
Transcoding?
Figure out VPN situation (keep the proton suite)
How to handle storage? ZFS? RAID? 
Need to figure out how to handle .env files
Is 1 service equal to 1 docker-compose or only 1 dockerfile? And then is 1 (say arr) stack 1 docker-compose or more? 
Is docker exclusive to servers or not? >> Depends on how I will setup devenv 
How to handle password manager? KeePassXC + Nextcloud? and/or Syncthing? Vaultwarden?
No networking yet. Thats a different rabbit hole
Think about smart home but with no big tech
StreamDeck+ as dashboard?
Separate family from my stuff

<< Personal Notes >>
Finish basic youtube filter to be usable
Youtube keyword filter (integrate it into filter?)
Zen Browser needs DRM for F1TV to work 
3D printing
Personal Website = Nix documentation? Or just .md files?
Robust proton mail filters


Example file structure from article. Not accurate to how I imagine it or my current version. 
```
├── docker
│   └── ghostfolio
│       └── docker-compose.yaml
├── hosts
│   └── myserver
│       ├── configuration.nix
│       ├── flake.lock
│       ├── flake.nix
│       ├── hardware-configuration.nix
│       └── modules
│           ├── docker
│           │   ├── authentik
│           │   │   ├── secrets.enc.env
│           │   │   └── secrets.env
│           │   └── beszel-agent
│           │       ├── prod.yaml
│           │       └── secrets.enc.env
│           └── server-components.nix
└── modules
    └── docker-compose
        └── default.nix
```
        
Example of new host structure (via google gemini) >> Needs to be fleshed out with said points above
``` json
{
  "desktop-pc": {
    "isServer": false,
    "secretsFile": "./secrets/desktop.yaml",
    "sshKeyPath": "/etc/ssh/ssh_host_ed25519_key"
  },
}

```

Example of a denful structure >> Does this align with my plans for the config?
```
hosts/
  laptop/
    _nixos/
      hardware.nix
      networking.nix
    _homeManager/
      shell.nix
users/
  alice/
    _homeManager/
      git.nix
    _nixos/
      groups.nix
```

Import-tree docs
``` nix
let
  my-tree = import-tree
    (i: i.addPath ./modules)
    (i: i.addAPI {
      desktop = self: self.filter (lib.hasInfix "/desktop/");
      server  = self: self.filter (lib.hasInfix "/server/");
      all     = self: self;
    });
in {
  # Use the desktop subset
  imports = [ my-tree.desktop ];

  # Or import everything
  # imports = [ my-tree.all ];
}
```

Please note that this is just a mind dump of researching. Nothing is final and there may be duplicate entries or even contradicting statements with others and/or the current state of the config. 
