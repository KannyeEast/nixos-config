{ ... }:
{
  flake.modules.homeManager.browserUserChrome =
    { ... }:
    {
      config = {
        programs.zen-browser.profiles.default.userChrome = ''
          /* ── typography ──────── */
          * {
              font-family: 'Inter', sans-serif;
          }

          /* ── surfaces ──────── */
          :root {
              --zen-border-radius: 8px !important;
          }

          /* Translucent tab strip; the window itself is transparent natively */
          .browserSidebarContainer {
              background-color: rgba(0, 0, 0, 0.226) !important;
          }

          #urlbar {
              border-radius: 8px !important;
          }

          #urlbar-background {
              border: 1px solid #ffffff13 !important;
          }

          .urlbarView-row[type="top_site"]:not([pinned]) {
              display: none !important;
          }

          /* Centre the tile grid rather than left-aligning a short row */
          #urlbar-results:has(.urlbarView-row[type="top_site"]) {
              justify-content: center !important;
          }

          /* "Switch to Tab" adds a second line and knocks that tile out of
             alignment with the rest of the grid. Badge the favicon instead. */
          .urlbarView-row[type="top_site"] .urlbarView-switchToTab {
              display: none !important;
          }

          .urlbarView-row[type="top_site"]:has(.urlbarView-switchToTab) .urlbarView-type-icon {
              background-color: currentColor;
              mask-image: url("data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23000' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><path d='M5 12h14'/><path d='M13 6l6 6-6 6'/></svg>");
              mask-size: contain;
              mask-repeat: no-repeat;
              mask-position: center;
          }

          /* ── tabs ──────── */
          .tabbrowser-tab .tab-background {
              transition: background-color 0.2s ease;
          }

          .tabbrowser-tab[pinned] .tab-background {
              border-top: 1px solid #ffffff1f !important;
              border-bottom: 1px solid #0000001f !important;
          }

          #TabsToolbar #firefox-view-button[open] > .toolbarbutton-icon,
          .tab-background:is([selected], [multiselected]) {
              box-shadow: none !important;
              border-top: 1px solid #ffffff2d !important;
              border-bottom: 1px solid #0000002d !important;
              background-color: rgba(255, 255, 255, 0.17) !important;
          }

          .tabbrowser-tab[pinned] .tab-background:is([selected], [multiselected]) {
              border-top: 1px solid #ffffff1f !important;
              border-bottom: 1px solid #0000001f !important;
          }

          /* Non-essential pins get a full box so they read as chips */
          .tabbrowser-tab[pinned]:not([zen-essential="true"]) .tab-stack .tab-background {
              border: 1px solid #ffffff13 !important;
          }

          .tabbrowser-tab[pinned]:not([zen-essential="true"]) .tab-stack .tab-background:is([selected], [multiselected]) {
              border-top: 1px solid #ffffff2d !important;
              border-bottom: 1px solid #0000002d !important;
              background-color: rgba(255, 255, 255, 0.17) !important;
          }

          /* @TODO: positional, not identity based. Reordering essentials
             moves the colours to different tabs. */
          .tabbrowser-tab[pinned]:nth-of-type(1) .tab-background:is([selected], [multiselected]) {
              background-color: rgba(255, 134, 134, 0.22) !important;
              box-shadow: none !important;
          }

          .tabbrowser-tab[pinned]:nth-of-type(2) .tab-background:is([selected], [multiselected]) {
              background-color: rgba(161, 197, 255, 0.22) !important;
              box-shadow: none !important;
          }

          /* Attention dot on changed background tabs */
          .tabbrowser-tab:is([image], [pinned]) > .tab-stack > .tab-content[attention]:not([selected]),
          .tabbrowser-tab > .tab-stack > .tab-content[pinned][titlechanged]:not([selected]) {
              background-image: radial-gradient(circle, #ffffff78, #ffffff1c 2px, transparent 2px) !important;
          }

          .tabbrowser-tab[pending="true"] .tab-icon-stack {
              opacity: 0.5;
          }

          .tab-icon-overlay {
              display: none !important;
          }

          /* Neutral dot instead of the Firefox logo on internal pages */
          .tab-icon-image[src="chrome://branding/content/icon32.png"],
          .tab-icon-image[src="chrome://browser/skin/privatebrowsing/favicon.svg"] {
              content: url("data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><circle cx='12' cy='12' r='9' fill='%23ffffff' fill-opacity='0.7'/></svg>") !important;
          }

          /* Keep closing tabs on screen long enough to animate out */
          .tabbrowser-tab:not([pinned], [fadein]) {
              transition-duration: 240ms, 240ms !important;
              transition-timing-function: ease-out, ease-out !important;
              visibility: visible !important;
          }

          .tab-content:not([fadein], [pinned])
          .tab-icon-pending:not([fadein]),
          .tab-icon-image:not([fadein]),
          .tab-label:not([fadein]) {
              visibility: visible !important;
          }

          .tab-label:not([fadein]) {
              display: flex !important;
          }

          .tab-close-button {
              width: 18px !important;
              height: 18px !important;
              padding: 5px !important;
              border-radius: 20px !important;
          }

          .close-icon {
              background-color: color-mix(in srgb, currentColor 10%, transparent) !important;
          }

          .close-icon:hover {
              background-color: color-mix(in srgb, currentColor 20%, transparent) !important;
          }

          /* ── folders ──────── */
          zen-folder {
              --folder-rail-inset: calc(4px + var(--tab-inline-padding, 8px) + 6px);

              margin: 0 !important;
              padding: 0 !important;

              & .tab-group-folder-icon {
                  opacity: 1 !important;
                  background-color: currentColor !important;
                  mask-image: url("data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23000' stroke-width='3' stroke-linecap='round' stroke-linejoin='round'><path d='M6 9l6 6 6-6'/></svg>");
                  mask-size: 14px 14px;
                  mask-repeat: no-repeat;
                  mask-position: center;
                  transition: rotate 0.2s ease !important;

                  & > svg {
                      display: none !important;
                  }
              }

              & .tab-group-label-container {
                  &:after {
                      display: none !important;
                  }
              }

              & .tab-group-label {
                  background: transparent !important;
                  border: unset !important;
                  font-weight: 500 !important;
                  text-align: unset !important;
                  color: var(--sidebar-text-color) !important;
              }

              & .tab-group-container {
                  position: relative !important;
                  margin-inline-start: var(--folder-rail-inset) !important;
                  padding-inline-start: 5px !important;
              }

              /* Rail runs first favicon centre to last, so it stops half
                 a tab short at each end instead of spanning the box */
              & .tab-group-container::before {
                  content: "";
                  position: absolute;
                  inset-block: calc(var(--tab-min-height, 36px) / 2);
                  inset-inline-start: -1px;
                  width: 2px;
                  border-radius: 1px;
                  background-color: color-mix(in srgb, currentColor 50%, transparent);
              }

              /* Collapse even when the active tab lives in this folder;
                 Zen otherwise keeps the container laid out */
              &[collapsed] .tab-group-container {
                  display: none !important;
              }

              & .tab-group-overflow-count {
                  font-weight: 400 !important;
                  opacity: 0.55;
              }

              &[collapsed] .tab-group-folder-icon {
                  rotate: -90deg;
              }
          }

          /* Live folders are fetched, not owned: sync glyph, no rotation */
          zen-folder:has(.reset-icon[live-folder-action]) .tab-group-folder-icon {
              mask-image: url("data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23000' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'><path d='M20 11a8.1 8.1 0 0 0-15.5-2m-.5-4v4h4'/><path d='M4 13a8.1 8.1 0 0 0 15.5 2m.5 4v-4h-4'/></svg>") !important;
              rotate: none !important;
          }

          /* Per-tab unload buttons, but keep live-folder status icons */
          .reset-icon:not([live-folder-action]) {
              display: none !important;
          }

          /* ── workspaces ──────── */
          #zen-workspaces-button {
              box-shadow: 0px 1px 10px rgba(0, 0, 0, 0.1) !important;
              border-radius: 8px !important;

              .subviewbutton {
                  &[active="true"] {
                      background: rgba(255, 255, 255, 0.1) !important;
                      border: 1px solid #ffffff0a !important;
                      box-shadow: 0px 0px 10px rgba(0, 0, 0, 0.062) !important;
                      transition: 0.3s !important;
                  }

                  &:hover {
                      background: rgba(255, 255, 255, 0.2) !important;
                      transition: 0.3s !important;
                  }

                  &:after {
                      display: none !important;
                  }
              }
          }

          #zen-current-workspace-indicator {
              padding: 10px calc(4px + var(--tab-inline-padding)) !important;
              font-weight: 500 !important;
          }

          .zen-workspace-close-unpinned-tabs-button {
              display: none;
          }

          @media (-moz-bool-pref: "zen.tabs.vertical") {
              #navigator-toolbox:is(#navigator-toolbox[zen-user-hover="true"][zen-has-hover], #navigator-toolbox[zen-user-hover="true"]:focus-within, #navigator-toolbox[zen-user-hover="true"][movingtab], #navigator-toolbox[zen-user-hover="true"][flash-popup], #navigator-toolbox[zen-user-hover="true"][has-popup-menu], #navigator-toolbox[zen-user-hover="true"]:has([open="true"]:not(tab):not(#zen-sidepanel-button)), #navigator-toolbox[zen-expanded="true"]:not([zen-user-hover="true"])) {
                  & #zen-essentials-container {
                      --tab-min-height: 47px !important;
                  }
              }
          }

          /* ── window controls ────────
             Icons stripped; blank translucent squares that colour on hover */
          .titlebar-button {
              background: none !important;
              padding: 8px 8px !important;
          }

          .titlebar-button > .toolbarbutton-icon {
              list-style-image: none;
              border-radius: 10px;
              background: #ffffff17 !important;
              border: 1px solid #ffffff21 !important;
              transition: 0.2s ease;
          }

          .titlebar-button:hover > .toolbarbutton-icon {
              background: #3aea4994 !important;
              border: 1px solid #3aea49 !important;
          }

          .titlebar-min:hover > .toolbarbutton-icon {
              background: #fac53794 !important;
              border: 1px solid #fac537 !important;
          }

          .titlebar-close:hover > .toolbarbutton-icon {
              background: #f34f5694 !important;
              border: 1px solid #f34f56 !important;
          }
        '';

        programs.zen-browser.profiles.default.userContent = ''
          @-moz-document url-prefix("about:newtab"), url-prefix("about:home") {
              .top-site-outer:not(:has(.icon-pin-small)) {
                  display: none !important;
              }
          }
        '';
      };
    };
}