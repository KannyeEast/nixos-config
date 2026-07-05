{ ... }:
{
    systems = [ "x86_64-linux" ];

    perSystem = { pkgs, ... }: {
        devShells.default = pkgs.mkShell {
            packages = [
                pkgs.just
                pkgs.nixfmt-rfc-style
                pkgs.deadnix
            ];
        };
    };
}