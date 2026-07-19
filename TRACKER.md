# Issue Tracker
## Simple checklist to keep track of functionality of all the modules

### Desktop
- [ ] Browser
  - Needs polish
  - Switch to ryze extensions if applicable
  - Make it more host driven → No default spaces/tabs/bookmarks, etc.
  - Put all browser settings into private Repo and let it all be declarative through profile
    - Figure out how to set all extension settings
- [ ] Audio
  - Not tested
- [ ] Bluetooth
  - Not tested
- [X] DE
- [ ] Shell
  - Not implemented
- [X] Directories
- [X] SDDM
- [ ] Dotfiles
  - Doesnt actually work
- [X] Fonts
- [X] Packages

### Dev
- [X] Debug
  - Minimal Setup
- [X] DevShell
  - Minimal Setup
- [X] DirEnv 
  - Minimal Setup

### Hardware
- [X] AMD
  - Works, might need refinement
- [X] Common
- [X] Intel
  - Works, might need refinement
- [X] Nvidia
  - Works, might need refinement

### Roles
- [X] Base
- [X] Desktop
- [X] Dev
- [X] Server

### Server
- [ ] Topology
  - Not implemented

### System
- [X] Boot
  - Works, maybe make own refind package?
- [X] Git
  - Works, authorization could be improved
  - YubiKeys?
- [X] Home Manager
- [ ] Impermanence
  - Not implemented, next on the list
- [X] Locale
- [ ] Networking
  - Fix secrets
- [X] Secrets
  - Sops itself works, needs to be polished and flawless implemented 
- [X] System
- [X] User

### Host
- [ ] Installer
  - Works but needs lots of tweaks
  - Secrets/Key management is not working correctly
  - Only for live env, not ISO ATM