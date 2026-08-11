# system

These files only get read by the config itself. Thus changes to the configs need to be followed by a `rebuild`

| Directory   | Read by                               | Ends up                               |
|-------------|---------------------------------------|---------------------------------------|
| `refind/`   | `modules/system/boot.nix`             | the ESP, via GRUB's `extraFiles`      |
| `grub/`     | `modules/system/boot.nix`             | `/boot/grub/themes/`                  |
| `plymouth/` | `modules/system/boot.nix`             | a wrapper derivation, then the initrd |
| `sddm/`     | `modules/desktop/display-manager.nix` | a wrapper derivation                  |
| `zen.json`  | `modules/desktop/browser`             | nowhere, read directly at eval        |

### Generated files

Some file are written by `just theme`/`flavours` and should not be edited by hand:
- `grub/theme.txt`
- `plymouth/theme`
- `zen.json` 
 
The templates that produce them live in `.config/flavours/templates/`.

---

### Presence is the switch

Modules get activated by the presence of a config folder (and file contents) rather than a manual toggle.
- Grub checks for `grub/theme.txt`
- Plymouth checks for `plymouth/theme`
- rEFInd checks for `refind/refind.conf`
- sddm checks for `sddm/theme.json`

If the config cannot find one of these file the module is either deactivated (`plymouth`, `rEFInd`) or simply has no 
theme (`grub`, `sddm`)

Note that without rEFInd dual-booting wont be supported.
