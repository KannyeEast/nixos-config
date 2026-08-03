{ lib, ... }:
let
  inherit (lib) concatMap filter optionalAttrs;

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
          icon = "data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'><rect width='64' height='64' rx='14' fill='%23e10600'/><path d='M25 19l22 13-22 13z' fill='%23fff'/></svg>";
          tags = [
            "shortcut"
            "streaming"
          ];
        }
        {
          name = "F1";
          url = "https://f1live.dpdns.org/1";
          icon = "data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'><rect width='64' height='64' rx='14' fill='%2315151e'/><circle cx='32' cy='32' r='5' fill='%23e10600'/><path d='M21 43a15 15 0 0 1 0-22' fill='none' stroke='%23e10600' stroke-width='5' stroke-linecap='round'/><path d='M43 21a15 15 0 0 1 0 22' fill='none' stroke='%23e10600' stroke-width='5' stroke-linecap='round'/></svg>";
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

  forBookmarks = map (
    b:
    if b ? bookmarks then
      b // { bookmarks = forBookmarks b.bookmarks; }
    else
      builtins.removeAttrs b [
        "icon"
        "iconSize"
      ]
  );

  # @TODO: unverified whether the urlbar honours this or only the new tab page.
  shortcuts = map (
    b:
    {
      inherit (b) url;
      label = b.name;
    }
    // optionalAttrs (b ? icon) {
      favicon = b.icon;
      faviconSize = b.iconSize or 96;
    }
  ) (filter (b: builtins.elem "shortcut" (b.tags or [ ])) (flatten tree));
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
          bookmarks.settings = forBookmarks tree;

          settings = {
            "browser.newtabpage.pinned" = builtins.toJSON shortcuts;
          };
        };
      };
    };
}
