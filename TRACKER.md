# Issue Tracker
## Simple checklist to keep track of functionality of all the modules

### Desktop
- [X] Browser
  - Figure out how to set all extension settings
    - Extensions using managed or sync storage can be declared
    - Local storage doesnt seem feasible
      - Check if userid exists in file and then append it or not (sponsorblock/dearrow)
  - Could maybe also move (partially) to dotfiles
  - Sync icon disappears when logged in to github; becomes normal folder icon
- [X] Audio
- [ ] Bluetooth
  - Not tested
- [X] DE
  - Needs polish, scripts, etc. Will take some time to get to 100%
- [ ] Shell
  - Custom shell, inspired by [ricelin](https://github.com/Gakuseei/Ricelin)
- [X] Directories
- [X] SDDM
- [X] Dotfiles
- [X] Fonts
- [X] Packages
- [X] Passwords
  - See if keepassxc works with cli only

### Server
- Profile nonexistent

### Dev
- Entire profile needs polish/rework pass

### Hardware
- [X] AMD
- [X] Common
- [X] Intel
- [X] Nvidia

### Roles
- [X] Base
- [ ] Main roles
  - [X] Desktop
  - [ ] Server
    - [X] Storage
    - [ ] Deploy-rs
- [ ] Add-ons
  - [ ] Dev
    - ide
    - editor
    - vm
  - [ ] Media
    - jellyfin
  - [ ] LLM
    - Ollama
  - [ ] 3D
    - Godot
    - Blender
  - [ ] Torrent

### System
- [X] Boot
- [X] Git
  - YubiKeys?
  - Git mail per forge
- [X] Home Manager
- [X] Impermanence
- [X] Locale
- [X] Networking
  - Append entries to secrets file automatically  
- [X] Secrets
- [X] SSH
- [X] System
- [X] User

### Config    
- [ ] Installer
  - Add support for submodules in dotfiles
- [ ] Readme
  - Create [anatomy diagram](https://codeberg.org/EmergentMind/nix-config#structure-quick-reference)
  - Also just update with configuration changes
- [X] Justfile
- [ ] Docs
  - Very much out of date