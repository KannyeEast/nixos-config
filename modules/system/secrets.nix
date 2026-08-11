{ inputs, ... }:
{
  flake.modules.nixos.secrets =
    { pkgs, host, ... }:
    let
      inherit (host) hostname user;
    in
    {
      imports = [
        inputs.sops-nix.nixosModules.sops
      ];

      config = {
        environment.systemPackages = [
          pkgs.sops
          pkgs.ssh-to-age
        ];

        environment.sessionVariables.SOPS_AGE_KEY_CMD = "ssh-to-age -private-key -i /home/${user.name}/.ssh/id_ed25519";

        sops = {
          defaultSopsFile = ../../hosts/${hostname}/secrets.json;

          defaultSopsFormat = "yaml";
          validateSopsFiles = false;

          age.sshKeyPaths = [ "/persistent/etc/ssh/ssh_host_ed25519_key" ];

          secrets = {
            userPrivateKey = {
              path = "/home/${user.name}/.ssh/id_ed25519";
              owner = user.name;
              mode = "0600";
            };
          };
        };
      };
    };
}
