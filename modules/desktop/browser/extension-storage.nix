{ lib, ... }:
let
    inherit (lib) concatMapStringsSep escapeShellArg;
in
{
    # Extensions built on maze-utils ignore managed storage, so their settings
    # cannot go through policies. They keep config in storage.sync, which is a
    # single SQLite file with one JSON blob per extension -- writable directly.
    #
    # Values are merged over what is already there, so counters and userID
    # survive. Declared keys win on every activation.
    flake.modules.homeManager.browserExtensionStorage = { config, pkgs, ... }:
    let
        profile = "${config.home.homeDirectory}/.config/zen/default";

        settings = {
            "sponsorBlocker@ajay.app" = {
                minDuration = 10;
                skipNoticeDuration = 5;
                renderSegmentsAsChapters = true;
                hideInfoButtonPlayerControls = true;

                permissions = {
                    sponsor = true;
                    selfpromo = true;
                    exclusive_access = true;
                    interaction = true;
                    intro = true;
                    outro = true;
                    preview = true;
                    hook = true;
                    music_offtopic = true;
                    filler = true;
                    poi_highlight = true;
                    chapter = false;
                };

                categorySelections = [
                    { name = "sponsor"; option = 1; }
                    { name = "poi_highlight"; option = 0; }
                    { name = "exclusive_access"; option = 0; }
                    { name = "chapter"; option = 0; }
                    { name = "preview"; option = 1; }
                ];
            };

            "deArrow@ajay.app" = {
                # ProtoConfig never reads managed storage, so the policy entry
                # cannot deliver this; it is a plain storage.sync key
                licenseKey = "AjI0L-6f166";

                casualMode = true;
                onlyShowCasualIconForCustom = true;
                showInfoAboutCasualMode = false;

                # Default is locale-dependent: TitleCase in English, else off
                titleFormatting = 2;

                replaceThumbnails = false;
                showLiveCover = false;
            };
        };

        apply = id: value: ''
            apply ${escapeShellArg id} ${escapeShellArg (builtins.toJSON value)}
        '';
    in
    {
        config = {
            home.activation.zenExtensionStorage =
                config.lib.dag.entryAfter [ "writeBoundary" ] ''
                    db="${profile}/storage-sync-v2.sqlite"

                    if [ ! -f "$db" ]; then
                        echo "zen: no storage-sync-v2.sqlite, skipping extension settings"
                    else
                        apply() {
                            local id="$1" declared="$2" cur merged escaped

                            cur=$(${pkgs.sqlite}/bin/sqlite3 "$db" \
                                "select data from storage_sync_data where ext_id = '$id';") || true

                            if [ -z "$cur" ]; then
                                echo "zen: no storage.sync row for $id, skipping"
                                return
                            fi

                            merged=$(printf '%s' "$cur" \
                                | ${pkgs.jq}/bin/jq -c --argjson d "$declared" '. * $d')

                            escaped=''${merged//\'/\'\'}

                            ${pkgs.sqlite}/bin/sqlite3 "$db" \
                                "update storage_sync_data set data = '$escaped' where ext_id = '$id';"
                        }

                        ${concatMapStringsSep "" (id: apply id settings.${id})
                            (builtins.attrNames settings)}
                    fi
                '';
        };
    };
}
