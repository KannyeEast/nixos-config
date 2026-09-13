{ inputs, ... }:
{
  flake.modules.nixos.system =
    {
      config,
      pkgs,
      host,
      user,
      ...
    }:
    let
      # cannot derive it from config.users.users.${user.name}.home because sops-nix needs it before the user exists
      home = "/home/${user.name}";
      
      # the key sops-nix decrypts with; derived from ssh.nix
      hostKeys = map (key: key.path) (
        builtins.filter (key: key.type == "ed25519") config.services.openssh.hostKeys
      );
    in
    {
      imports = [ inputs.sops-nix.nixosModules.sops ];

      config = {
        environment.systemPackages = [
          pkgs.sops
          pkgs.ssh-to-age
        ];
        
        # lets sops run as the user against the deployed key below; no need for a separate age key stored on any machine
        environment.sessionVariables.SOPS_AGE_KEY_CMD = "ssh-to-age -private-key -i ${home}/.ssh/id_ed25519";

        sops = {
          defaultSopsFile = ../../hosts/${host.name}/secrets.json;
          defaultSopsFormat = "yaml"; # setting this to json breaks sops-nix; works fine with yaml 
          validateSopsFiles = false;

          age.sshKeyPaths = hostKeys;

          # host key decrypts -> becomes user key -> SOPS_AGE_KEY_CMD uses key to edit secrets 
          secrets.user-privatekey = {
            path = "${home}/.ssh/id_ed25519";
            owner = user.name;
            mode = "0600";
          };
        };
      };
    };
}
