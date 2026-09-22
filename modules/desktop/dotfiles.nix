{
  flake.modules.homeManager.desktop =
    {
      config,
      lib, 
      pkgs,
      host,
      flake,
      ...
    }:
    let
      source = "${flake}/hosts/${host.name}/home";
      target = config.home.homeDirectory;
      
      # hosts/<host>/home mirrors $HOME itself:
      # home/.zshrc              -> ~/.zshrc
      # home/.config/niri/...    -> ~/.config/niri/...
      sync = pkgs.writeShellApplication {
        name = "dotfiles-sync";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.findutils
        ];
        text = ''
          src=${lib.escapeShellArg source}
          dst=${lib.escapeShellArg target}

          [ -d "$src" ] || { echo "dotfiles: $src does not exist" >&2; exit 1; }

          # link every file, creating directories as needed
          while IFS= read -r rel; do
            link="$dst/$rel"

            # never edit an existing $HOME file that is not linked to this hosts home/ config
            if [ -e "$link" ] && [ ! -L "$link" ]; then
              echo "dotfiles: $link is a real file, backing it up" >&2
              mv -- "$link" "$link.bak"
            fi

            mkdir -p -- "$(dirname -- "$link")"
            ln -sfnT -- "$src/$rel" "$link"
          done < <(find "$src" -type f -printf '%P\n')

          # drop links when the source is gone
          while IFS= read -r top; do
            [ -e "$dst/$top" ] || continue
            find "$dst/$top" -xtype l -lname "$src/*" -delete
          done < <(find "$src" -mindepth 1 -maxdepth 1 -printf '%P\n')
        '';
      };
    in
    {
      config = {
        home.packages = [ sync ];

        # first pass at activation
        home.activation.dotfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          ${lib.getExe sync} || true
        '';

        systemd.user.services.dotfiles = {
          Unit.Description = "Mirror the host's dotfiles into $HOME";
          Install.WantedBy = [ "default.target" ];

          Service = {
            # second pass on change; watch the source directory for changes
            ExecStart = "${pkgs.writeShellScript "dotfiles-watch" ''
              while :; do
                ${lib.getExe sync} || true
                ${lib.getExe' pkgs.inotify-tools "inotifywait"} \
                  -r -q -e create,delete,move,close_write \
                  ${lib.escapeShellArg source} >/dev/null || true
                sleep 0.2
              done
            ''}";
            Restart = "always";
          };
        };
      };
    };
}
