{
  flake.modules.nixos.audio =
    { pkgs, ... }:
    {
      config = {
        services.pulseaudio.enable = false;
        security.rtkit.enable = true;

        services.pipewire = {
          enable = true;
          alsa.enable = true;
          alsa.support32Bit = true;
          pulse.enable = true;
        };

        environment.systemPackages = [
          pkgs.pavucontrol
          pkgs.pamixer
        ];
      };
    };
}
