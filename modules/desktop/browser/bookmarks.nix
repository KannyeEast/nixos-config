{ lib, ... }:
let
  inherit (lib) concatMap filter;

  # Anything tagged "shortcut" also becomes a new-tab tile
  tree = [
    {
      name = "Tools";
      bookmarks = [
        {
          name = "Regex";
          url = "https://regex101.com/";
          tags = [
            "shortcut"
            "tool"
          ];
        }
      ];
    }
    {
      name = "Streaming";
      bookmarks = [
        {
          name = "F1TV";
          url = "https://f1tv.formula1.com/";
          tags = [
            "shortcut"
            "streaming"
          ];
        }
        {
          name = "F1";
          url = "https://f1live.dpdns.org/1";
          tags = [
            "shortcut"
            "streaming"
          ];
        }
        {
          name = "Football";
          url = "https://streamed.pk/";
          tags = [
            "shortcut"
            "streaming"
          ];
        }
      ];
    }
  ];

  flatten = items: concatMap (b: if b ? bookmarks then flatten b.bookmarks else [ b ]) items;

  shortcuts = map (b: {
    inherit (b) url;
    label = b.name;
  }) (filter (b: builtins.elem "shortcut" (b.tags or [ ])) (flatten (tree)));
in
{
  # user-chrome.nix sizes the urlbar from how many tiles there are
  flake.lib.browserShortcuts = shortcuts;

  flake.modules.homeManager.browserBookmarks =
    { ... }:
    {
      config = {
        programs.zen-browser.profiles.default = {
          bookmarks.force = true;
          bookmarks.settings = tree;

          settings = {
            "browser.newtabpage.pinned" = builtins.toJSON shortcuts;
          };
        };
      };
    };
}
