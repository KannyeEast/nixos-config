{ inputs, lib, ... }:
let
  inherit (lib)
    mkOption
    types
    ;
in
{
  flake.modules.nixos.system =
    {
      config,
      pkgs,
      user,
      ...
    }:
    let
      inherit (config.internal)
        system
        ;

      home = config.users.users.${user.name}.home;
      persist = system.impermanence.root;

      # grab what disko is naming the disk
      rootDevice = config.fileSystems."/".device;
    in
    {
      imports = [ inputs.impermanence.nixosModules.impermanence ];

      options = {
        internal.system.impermanence = {
          root = mkOption {
            type = types.str;
            default = "/persist";
            internal = true;
            description = "Where the persisted state lives";
          };
          directories = mkOption {
            type = types.listOf (types.either types.str (types.attrsOf types.anything));
            default = [ ];
            internal = true;
            description = "Directories that should persist";
          };
          files = mkOption {
            type = types.listOf types.str;
            default = [ ];
            internal = true;
            description = "Files that should persist";
          };
        };
      };

      config = {
        internal.system.impermanence = {
          directories = [
            "/var/lib/NetworkManager"
            "/var/lib/nixos"
            "/var/lib/systemd"
            "/var/log"
          ];
          files = [
            "/etc/machine-id"
          ];
        };

        fileSystems.${persist}.neededForBoot = true;

        boot.initrd.systemd.enable = true;
        boot.initrd.systemd.initrdBin = [
          pkgs.btrfs-progs
          pkgs.coreutils
          pkgs.findutils
        ];
        boot.initrd.systemd.services.rollback = {
          description = "Reset the root subvolume to a blank state";
          wantedBy = [ "initrd.target" ];
          after = [ "initrd-root-device.target" ];
          before = [ "sysroot.mount" ];
          unitConfig.DefaultDependencies = "no";
          serviceConfig.Type = "oneshot";
          script = ''
            mkdir -p /btrfs_tmp
            mount -o subvol=/ ${rootDevice} /btrfs_tmp

            # keep root for 30 days before fully deleting them
            if [[ -e /btrfs_tmp/root ]]; then
              mkdir -p /btrfs_tmp/old_roots
              timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%d_%H:%M:%S")
              mv /btrfs_tmp/root "/btrfs_tmp/old_roots/$timestamp"
            fi

            delete_subvolume_recursively() {
              IFS=$'\n'
              for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
                delete_subvolume_recursively "/btrfs_tmp/$i"
              done
              btrfs subvolume delete "$1"
            }

            for i in $(find /btrfs_tmp/old_roots/ -mindepth 1 -maxdepth 1 -mtime +30); do
              delete_subvolume_recursively "$i"
            done

            btrfs subvolume create /btrfs_tmp/root

            umount /btrfs_tmp
          '';
        };

        # impermanence creates the bind-bind as root; this hands back the directories to the user
        systemd.tmpfiles.rules = [
          "Z ${persist}${home} - ${user.name} users -"
        ];

        environment.persistence.${persist} = {
          hideMounts = true;
          directories = system.impermanence.directories;
          files = system.impermanence.files;
        };
      };
    };
}
