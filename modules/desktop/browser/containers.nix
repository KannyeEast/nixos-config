{ ... }:
{
    # @TODO: Hoist container data to the host profile (extensions.nix pattern).
    # Containers are per-host identity data and carry the userContextIds that
    # move to the private repo later
    flake.modules.homeManager.browserContainers = { ... }:
    {
        config = {
            programs.zen-browser.profiles.default = {
                containersForce = true;
                containers = {
                    "Main" = {
                        color = "toolbar";
                        icon = "fingerprint";
                        id = 1;
                    };
                    "Music" = {
                        color = "purple";
                        icon = "chill";
                        id = 2;
                    };
                    "Coding" = {
                        color = "blue";
                        icon = "fingerprint";
                        id = 3;
                    };
                    "Server" = {
                        color = "red";
                        icon = "fingerprint";
                        id = 4;
                    };
                };
            };
        };
    };
}