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
        
        users.users.${user.name}.extraGroups = [
          "libvirtd"
          "kvm" 
        ];
        
        environment.systemPackages = [
          pkgs.virt-manager
          pkgs.virt-viewer
          pkgs.virtio-win
          pkgs.spice
          pkgs.spice-gtk
          pkgs.spice-protocol
          pkgs.win-spice
          pkgs.adwaita-icon-theme
        ];
        
        programs.dconf.enable = true;

        # virsh uses qemu:///session by default; without this every virsh command reports an empty list
        environment.sessionVariables.LIBVIRT_DEFAULT_URI = "qemu:///system";
        
        virtualisation = {
          libvirtd = {
            enable = true;
  
            # manual start of vm only
            onBoot = "ignore";
            onShutdown = "shutdown";
  
            qemu = {
              package = pkgs.qemu_kvm;
              runAsRoot = false;
  
              # enable tpm emulation; required by win11
              swtpm.enable = true;
              vhostUserPackages = [ pkgs.virtiofsd ];
            };
          };
          
          spiceUSBRedirection.enable = true;
        };
        
        services.spice-vdagentd.enable = true;

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
