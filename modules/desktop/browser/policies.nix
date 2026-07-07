{ ... }:
let
in
{
    flake.modules.homeManager.browserPolicies = { ... }:
    let
        mkPolicy = builtins.mapAttrs (_: Value: { inherit Value; });
    in
    {
        # about:policies#documentation
        programs.zen-browser.policies = {
            AIControls.Default = "blocked"; 
            AppAutoUpdate = false;
            # Authentication >> Might be useful to look at later
            AutofillAddressEnabled = false;
            AutofillCreditCardEnabled = false;
            BackgroundAppUpdate = false;
            BrowserDataBackup = {
                AllowBackup = false;
                AllowRestore = false;
            };
            Certificates.ImportEnterpriseRoots = true;
            # Can probably do more for cookies
            Cookies = {
                Allow = [
                    "file:///"
                    "http://proton.me" "https://proton.me"
                    "http://kagi.com" "https://kagi.com"
                    "http://simplelogin.io" "https://simplelogin.io"
                ];
                Behavior = "reject-tracker-and-partition-foreign";
                BehaviorPrivateBrowsing = "reject-tracker-and-partition-foreign";
            };
            DisableAppUpdate = true;
            DisableFeedbackCommands = true;
            DisableFirefoxStudies = true;
            DisableSetDesktopBackground = true;
            DisableTelemetry = true;
            DisplayBookmarksToolbar = "never";
            DNSOverHTTPS = {
                Enabled = true;
                ProviderURL = "https://mozilla.cloudflare-dns.com/dns-query";
                Fallback = true;
            };
            DontCheckDefaultBrowser = true;
            EnableTrackingProtection = {
                Category = "strict";
                BaselineExceptions = true;
            };
            FirefoxHome = {
                Search = true;
                Weather = false;
                TopSites = false;
                SponsoredTopSites = false;
                Highlights = false;
                Pocket = false;
                Stories = false;
                SponsoredPocket = false;
                SponsoredStories = false;
                Snippets = false;
            };
            FirefoxSuggest = {
                WebSuggestions = false;
                SponsoredSuggestions = false;
                ImproveSuggest = false;
            };
            GenerativeAI.Enable = false;
            HardwareAcceleration = true;
            Homepage = { 
                URL = "https://kagi.com";
                Additional = [ "about:blank" ];
                StartPage = "homepage";
            };
            HttpsOnlyMode = "allowed";
            InstallAddonsPermission = {
                Allow = [ "https://addons.mozilla.org" "https://addons.mozilla.org^privateBrowsingId=1" ];
                Default = false;
            };
            NetworkPrediction = false;
            NewTabPage = false;
            NoDefaultBookmarks = true;
            OfferToSaveLogins = false;
            PasswordManagerEnabled = false;
            Permissions = {
                Camera = {
                    Allow = [ ];
                    Block = [ ];
                    BlockNewRequests = false;
                };
                Microphone = {
                    Allow = [ ];
                    Block = [ ];
                    BlockNewRequests = false;
                };
                Location = {
                    Allow = [ ];
                    Block = [ ];
                    BlockNewRequests = true;
                };
                Notifications = {
                    Allow = [ ];
                    Block = [ ];
                    BlockNewRequests = true;
                };
                Autoplay = {
                    Allow = [ ];
                    Block = [ ];
                    BlockNewRequests = true;
                };
                VirtualReality = {
                    Allow = [ ];
                    Block = [ ];
                    BlockNewRequests = true;
                };
                ScreenShare = {
                    Allow = [ ];
                    Block = [ ];
                    BlockNewRequests = true;
                };
            };
            PictureInPicture.Enabled = false;
            PopupBlocking.Default = false;
            PrintingEnabled = true;
            PromptForDownloadLocation = true;
            SanitizeOnShutdown = {
                Cache = true;
                Cookies = true;
                FormData = true;
                History = true;
                Sessions = false;
                SiteSettings = false;
            };
            SearchBar = "unified"; 
            SearchSuggestEnabled = false;
            ShowHomeButton = true;
            SkipTermsOfUse = true;
            StartDownloadsInTempDirectory = true;
            VisualSearchEnabled = true;
        
            Preferences = mkPolicy {
                "browser.translations.automaticallyPopup" = false;
                "browser.tabs.warnOnClose" = false;
            };
        };
        
        # @TODO: Still need to look through `Preferences` and `settings`
        programs.zen-browser.profiles.default.settings = {
            "zen.pinned-tab-manager.restore-pinned-tabs-to-pinned-url" = true;
            "zen.tabs.ctrl-tab.ignore-pending-tabs" = true;
            "zen.tabs.select-recently-used-on-close" = false;
            "zen.ui.migration.compact-mode-button-added" = true;
            "zen.view.compact.enable-at-startup" = false;
            "zen.view.show-newtab-button-top" = false;
            "zen.view.use-single-toolbar" = false;
            "zen.view.window.scheme" = 0;
            "zen.welcome-screen.seen" = true;
            "zen.workspaces.indicator-name-center" = true;
            "zen.workspaces.show-workspace-indicator" = true;
        };
    };
}