{ lib, ... }:
let
  inherit (lib)
    mkIf
    ;
in
{
  flake.modules.nixos.virt =
    {
      config,
      pkgs,
      host,
      user,
      ...
    }:
    let
      # guest disks; the path libvirt hands to qemu
      images = "/var/lib/libvirt/images";

      # host side of the virtiofs share; work done in the vm is saved to this directory
      shared = "${config.users.users.${user.name}.home}/vm";
    in
    {
      config = mkIf (host.class == "desktop") {
        internal.system.impermanence.directories = [
          {
            directory = "/var/lib/libvirt";
            mode = "0755";
          }
        ];
      
        virtualisation.libvirtd = {
          enable = true;

          # manual start of vm only
          onBoot = "ignore";
          onShutdown = "suspend";

          qemu = {
            package = pkgs.qemu_kvm;
            runAsRoot = false;

            # enable tpm emulation; required by win11
            swtpm.enable = true;
            ovmf = {
              enable = true;
              packages = [ pkgs.OVMFFull.fd ];
            };
          };
        };
        
        virtualisation.spiceUSBRedirection.enable = true;

        programs.virt-manager.enable = true;
        users.users.${user.name}.extraGroups = [
          "libvirtd"
          "kvm" 
        ];

        environment.systemPackages = [
          pkgs.virtiofsd # host side of the shared folder
          pkgs.virtio-win # guest drivers: disk, network, virtiofs
          pkgs.win-spice # guest clipboard and display resize
        ];

        systemd.tmpfiles.rules = [
          # create <images> dir with mode 0755 and user:group as root:root
          "d ${images} 0755 root root - -"

          "h ${images} - - - - +C"

          # create <shared> dir with mode 0755 and user:group as <user>:users
          "d ${shared} 0755 ${user.name} users - -"
        ];

        # libvirt's NAT bridge;
        networking.firewall.trustedInterfaces = [ "virbr0" ];
      };
    };
}
