## rEFInd-darkflake

A clean, dark, minimal theme for the [rEFInd](http://www.rodsbooks.com/refind/) UEFI boot manager.

This repo exists so I can tweak the theme files to work with my personal NixOS configuration. \
The theme icons mainly come from [andersfischernielsen/rEFInd-minimal-black](https://github.com/andersfischernielsen/rEFInd-minimal-black).

### Installation
Despite the name this is not actually a NixOS flake. You still need to get the files onto your ESP yourself.
Either copy them to `/boot/EFI/refind/themes/rEFInd-darkflake`, or use the
[`boot.loader.refind`](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/system/boot/loader/refind/refind.nix)
options in nixpkgs. Note that module has no theme option, so you'd use `additionalFiles` to place the theme
and `extraConfig` for the include line below.

Then enable the theme by adding this to the end of your `refind.conf`:

```conf
include themes/rEFInd-darkflake/theme.conf
```

Here's an example menuentry configuration

```conf
menuentry "NixOS" {
    icon /EFI/refind/themes/rEFInd-darkflake/icons/os_nixos.png
    loader /EFI/NixOS-boot/grubx64.efi
}
 
menuentry "Windows" {
    icon /EFI/refind/themes/rEFInd-darkflake/icons/os_win.png
    loader /EFI/Microsoft/Boot/bootmgfw.efi
}
```

Entry detection depends on your main rEFInd `.conf` file. Just make sure to point the icon at
`/EFI/refind/themes/rEFInd-darkflake/icons/<os_icon.png>`

### Attribution & licence

- Black theme: [andersfischernielsen](https://github.com/andersfischernielsen/rEFInd-minimal-black)
- Original theme: [evanpurkhiser](https://github.com/evanpurkhiser/rEFInd-minimal)
- OS icons: [Lightness for burg](http://sworiginal.deviantart.com/art/Lightness-for-burg-181461810)
  by [SWOriginal](http://sworiginal.deviantart.com/)
\
\
  MIT [`LICENSE`](LICENSE).