# rEFInd-dark-theme

A clean, dark, minimal theme for the [rEFInd](http://www.rodsbooks.com/refind/) UEFI boot manager.

Forked from [andersfischernielsen/rEFInd-minimal-black](https://github.com/andersfischernielsen/rEFInd-minimal-black), tweaked for personal use.

## Installation

1. Copy the theme files to your ESP:
```plantuml
/boot/EFI/refind/themes/rEFInd-dark-theme/
```

2. Then add this to your `refind.conf`:
```conf
include themes/rEFInd-dark-theme/theme.conf
```

Example manual menuentries:

```plantuml
menuentry "NixOS" {
    icon /EFI/refind/themes/rEFInd-dark-theme/icons/os_nixos.png
    loader /EFI/NixOS-boot/grubx64.efi
}

menuentry "Windows" {
    icon /EFI/refind/themes/rEFInd-dark-theme/icons/os_win.png
    loader /EFI/Microsoft/Boot/bootmgfw.efi
}
```

Just make sure your icon paths point at `themes/rEFInd-dark-theme/icons/<os_icon.png>`.

## Credits

- Original theme: [evanpurkhiser/rEFInd-minimal](https://github.com/evanpurkhiser/rEFInd-minimal)
- Dark theme: [andersfischernielsen/rEFInd-minimal-black](https://github.com/andersfischernielsen/rEFInd-minimal-black)
- Icons: [SWOriginal](https://www.deviantart.com/sworiginal/art/Lightness-for-burg-181461810)