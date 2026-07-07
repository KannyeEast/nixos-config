{ ... }:
{
    flake.modules.homeManager.browserExtensions = { ... }:
    let
        mkExtensionSettings = builtins.mapAttrs (_: entry:
            if builtins.isAttrs entry
            then entry
            else mkExtensionEntry {id = entry;});
            
        mkExtensionEntry = { id, pinned ? false }:
        let
            base = {
                install_url = "https://addons.mozilla.org/firefox/downloads/latest/${id}/latest.xpi";
                installation_mode = "force_installed";
            };
        in
            if pinned
            then base // { default_area = "navbar"; }
            else base // { default_area = "menupanel"; };   
    in
    {
        # @TODO: Need to configure extension settings
        # Entry = about:debugging#/runtime/this-firefox
        # Id = https://addons.mozilla.org/en-US/firefox/addon/<extension>
        config = {
            programs.zen-browser.policies = {
                ExtensionSettings = mkExtensionSettings {
                    "vpn@proton.ch" = mkExtensionEntry {
                        id = "proton-vpn-firefox-extension";
                        pinned = true;
                    };
                    "uBlock0@raymondhill.net" = mkExtensionEntry {
                        id = "ublock-origin";
                        pinned = true;
                    };
                    "keepassxc-browser@keepassxc.org" = mkExtensionEntry {
                        id = "keepassxc-browser";
                        pinned = true;
                    };
                    "78272b6fa58f4a1abaac99321d503a20@proton.me" = mkExtensionEntry {
                        id = "proton-pass";
                        pinned = true;
                    };
                    "namlet@pax.red" = mkExtensionEntry {
                        id = "namlet";
                        pinned = true;
                    };
                    "{a6c4a591-f1b2-4f03-b3ff-767e5bedf4e7}" = mkExtensionEntry {
                        id = "user-agent-string-switcher";
                        pinned = true;
                    };
                    "{d867162c-4c38-4c5f-aca4-db6a6592d7da}" = "youtube-tweaks";
                    "deArrow@ajay.app" = "dearrow";
                    "sponsorBlocker@ajay.app" = "sponsorblock";
                    "firefox@tampermonkey.net" = "tampermonkey";
                    "{b86e4813-687a-43e6-ab65-0bde4ab75758}" = "localcdn-fork-of-decentraleyes";
                    "harper@writewithharper.com" = "private-grammar-checker-harper";
                    "{b8326f03-322f-4112-96bd-e7996548d99f}" = "theater-mode-for-youtube";
                    "{9076cefe-e6f8-4883-a480-9f968bd09249}" = "reddit-nsfw-unblocker";
                };
                
                "3rdparty".Extensions = {
                    "uBlock0@raymondhill.net".adminSettings = builtins.toJSON {
                        userSettings = {
                            uiTheme = "dark";
                        };
                        
                        selectedFilterLists = [
                            "user-filters"
                            "ublock-filters"
                            "ublock-badware"
                            "ublock-privacy"
                            "ublock-quick-fixes"
                            "ublock-unbreak"
                            "easylist"
                            "easyprivacy"
                            "urlhaus-1"
                            "plowe-0"
                            "fanboy-cookiemonster"
                            "ublock-cookies-easylist"
                            "fanboy-social"
                            "fanboy-ai-suggestions"
                            "easylist-chat"
                            "easylist-newsletters"
                            "easylist-notifications"
                            "easylist-annoyances"
                            "DEU-0"
                        ];
                        
                        whitelist = [
                            "chrome-extension-scheme"
                            "moz-extension-scheme"
                        ];
                        
                        dynamicFilteringString = ''
                            * vo.aicdn.com * noop
                            * ajax.googleapis.com * noop
                            * js.appboycdn.com * noop
                            * ajax.aspnetcdn.com * noop
                            * materialdesignicons.b-cdn.net * noop
                            * libs.baidu.com * noop
                            * lib.baomitu.com * noop
                            * apps.bdimg.com * noop
                            * cdn.bootcdn.net * noop
                            * cdn.bootcss.com * noop
                            * maxcdn.bootstrapcdn.com * noop
                            * netdna.bootstrapcdn.com * noop
                            * stackpath.bootstrapcdn.com * noop
                            * ajax.cloudflare.com * noop
                            * cdnjs.cloudflare.com * noop
                            * use.fontawesome.com.cdn.cloudflare.net * noop
                            * code.createjs.com * noop
                            * cdn.datatables.net * noop
                            * cdn.embed.ly * noop
                            * use.fontawesome.com * noop
                            * fonts.googleapis.com * noop
                            * sdn.inbond.gslb.geekzu.org * noop
                            * sdn.geekzu.org * noop
                            * gitcdn.github.io * noop
                            * gstaticadssl.l.google.com * noop
                            * fonts.gstatic.com * noop
                            * mat1.gtimg.com * noop
                            * cds.s5x3j6q5.hwcdn.net * noop
                            * apps.bdimg.jomodns.com * noop
                            * code.jquery.com * noop
                            * jsdelivr.map.fastly.net * noop
                            * cdn.jsdelivr.net * noop
                            * akamai-webcdn.kgstatic.net * noop
                            * lib.sinaapp.com * noop
                            * ajax.loli.net * noop
                            * cdnjs.loli.net * noop
                            * fonts.loli.net * noop
                            * cdn.embed.ly.cdn.cloudflare.net * noop
                            * cdn.bootcss.com.maoyundns.com * noop
                            * cdn.bootcdn.net.maoyundns.com * noop
                            * cdn.materialdesignicons.com * noop
                            * cdn.mathjax.org * noop
                            * ajax.microsoft.com * noop
                            * mscomajax.vo.msecnd.net * noop
                            * cdn.jsdelivr.net.cdn.cloudflare.net * noop
                            * ajax.loli.net.cdn.cloudflare.net * noop
                            * cdnjs.loli.net.cdn.cloudflare.net * noop
                            * fonts.loli.net.cdn.cloudflare.net * noop
                            * akamai-webcdn.kgstatic.net.edgesuite.net * noop
                            * dualstack.osff.map.fastly.net * noop
                            * pagecdn.io * noop
                            * cdn.plyr.io * noop
                            * lib.baomitu.com.qh-cdn.com * noop
                            * iduwdjf.qiniudns.com * noop
                            * mat1.gtimg.com.tegsea.tc.qq.com * noop
                            * cdn.ravenjs.com * noop
                            * mathjax.rstudio.com * noop
                            * developer.n.shifen.com * noop
                            * lb.sae.sina.com.cn * noop
                            * cdn.staticfile.org * noop
                            * unpkg.com * noop
                            * upcdn.b0.upaiyun.com * noop
                            * gateway.cname.ustclug.org * noop
                            * ajax.proxy.ustclug.org * noop
                            * yandex.st * noop
                            * yastatic.net * noop
                            * vjs.zencdn.net * noop
                            behind-the-scene * * noop
                            behind-the-scene * 1p-script noop
                            behind-the-scene * 3p noop
                            behind-the-scene * 3p-frame noop
                            behind-the-scene * 3p-script noop
                            behind-the-scene * image noop
                            behind-the-scene * inline-script noop
                        ''; 
                        
                        hostnameSwitchesString = ''
                            no-csp-reports: * true
                            no-large-media: behind-the-scene false
                        '';
                        
                        userFilters = ''
                            accounts.google.com/gsi/*
                            
                            ! YouTube
                            www.youtube.com###voice-search-button
                            www.youtube.com##ytd-notification-topbar-button-renderer.ytd-masthead.style-scope
                            www.youtube.com##ytd-button-renderer.ytd-masthead.style-scope
                            youtube.com##ytd-guide-section-renderer:has([href="/feed/subscriptions"]) #items>:not(:first-child)
                            youtube.com##ytd-rich-section-renderer:has-text(Most relevant)
                            youtube.com##ytd-reel-shelf-renderer:has-text(Most relevant)
                            www.youtube.com##ytd-guide-section-renderer.ytd-guide-renderer.style-scope:nth-of-type(6)
                            www.youtube.com###section-items > ytd-guide-entry-renderer.ytd-guide-collapsible-section-entry-renderer.style-scope > .ytd-guide-entry-renderer.style-scope.yt-simple-endpoint
                            www.youtube.com###section-items
                            www.youtube.com###copyright
                            www.youtube.com###guide-links-secondary
                            www.youtube.com###guide-links-primary
                            youtube.com##span[id*="country-code"]
                            www.youtube.com##.yt-core-attributed-string--inline-block-mod
                            www.youtube.com##.yt-badge-shape__icon
                            www.youtube.com##.ytdChipsShelfWithVideoShelfRendererHost > div
                            www.youtube.com###top-level-buttons-computed
                            
                            ! Reddit 
                            www.reddit.com##faceplate-expandable-section-helper
                            www.reddit.com##faceplate-tracker[noun*="explore"]
                            www.reddit.com##faceplate-tracker[noun*="all"]
                            www.reddit.com##li.left-nav-create-community-button[slot="sr-creation-entrypoint-experiment"]
                            www.reddit.com##hr.my-sm 
                            www.reddit.com##.mb-md.mx-md.flex.justify-self-end.legal-links
                            www.reddit.com##.mb-md.mx-md.flex.\!mx-0.legal-links
                            reddit.com##reddit-search-large[show-ask-button]:remove-attr(show-ask-button)
                            ||www.redditstatic.com/shreddit/search-input-desktop-client-css$css,domain=reddit.com
                            www.reddit.com##reddit-search-large[show-snoo-leading-icon]:remove-attr(show-snoo-leading-icon)
                            www.reddit.com##div.h-\[40px\].flex:nth-of-type(1)
                            www.reddit.com##recent-posts
                            www.reddit.com###left-sidebar-container > faceplate-tracker
                            www.reddit.com###right-sidebar-container
                        '';
                    };
                };
                
                home.file = 
                let
                    sponsorBlock = {
                        renderSegmentsAsChapters = true;
                        changeChapterColor = true;
                        colorPalette = {
                            red = "#780303";
                            white = "#ffffff";
                            locked = "#ffc83d";
                        };
                        chapterCategoryAdded = true;
                        showZoomToFillError2 = false;
                        autoSkipOnMusicVideosUpdate = true;
                        userID = "@TODO: Secret here";
                        allowScrollingToEdit = true;
                        barTypes = {
                            preview-chooseACategory = {
                                color = "#ffffff";
                                opacity = "0.7";
                            };
                            sponsor = {
                                color = "#00d400";
                                opacity = "0.7";
                            };
                            preview-sponsor = {
                                color = "#007800";
                                opacity = "0.7";
                            };
                            selfpromo = {
                                color = "#ffff00";
                                opacity = "0.7";
                            };
                            preview-selfpromo = {
                                color = "#bfbf35";
                                opacity = "0.7";
                            };
                            exclusive_access = {
                                color = "#008a5c";
                                opacity = "0.7";
                            };
                            interaction = {
                                color = "#cc00ff";
                                opacity = "0.7";
                            };
                            preview-interaction = {
                                color = "#6c0087";
                                opacity = "0.7";
                            };
                            intro = {
                                color = "#00ffff";
                                opacity = "0.7";
                            };
                            preview-intro = {
                                color = "#008080";
                                opacity = "0.7";
                            };
                            outro = {
                                color = "#0202ed";
                                opacity = "0.7";
                            };
                            preview-outro = {
                                color = "#000070";
                                opacity = "0.7";
                            };
                            preview = {
                                color = "#008fd6";
                                opacity = "0.7";
                            };
                            preview-preview = {
                                color = "#005799";
                                opacity = "0.7";
                            };
                            hook = {
                                color = "#395699";
                                opacity = "0.8";
                            };
                            preview-hook = {
                                color = "#273963";
                                opacity = "0.7";
                            };
                            music_offtopic = {
                                color = "#ff9900";
                                opacity = "0.7";
                            };
                            preview-music_offtopic = {
                                color = "#a6634a";
                                opacity = "0.7";
                            };
                            poi_highlight = {
                                color = "#ff1684";
                                opacity = "0.7";
                            };
                            preview-poi_highlight = {
                                color = "#9b044c";
                                opacity = "0.7";
                            };
                            filler = {
                                color = "#7300FF";
                                opacity = "0.9";
                            };
                            preview-filler = {
                                color = "#2E0066";
                                opacity = "0.7";
                            };
                            chapter = {
                                color = "#ffd983";
                                opacity = "0";
                            };
                        };
                        categorySelections = [
                            {
                                name = "sponsor";
                                option = 1;
                            }
                            {
                                name = "poi_highlight";
                                option = 1;
                            }
                            {
                                name = "exclusive_access";
                                option = 0;
                            }
                            {
                                name = "chapter";
                                option = 0;
                            }
                        ];
                        categoryPillUpdate = true;
                        isVip = false;
                        invidiousInstances = [
                            "www.youtubekids.com"
                            "inv.nadeko.net"
                            "inv.tux.pizza"
                            "invidious.adminforge.de"
                            "invidious.jing.rocks"
                            "invidious.nerdvpn.de"
                            "invidious.perennialte.ch"
                            "invidious.privacyredirect.com"
                            "invidious.reallyaweso.me"
                            "invidious.yourdevice.ch"
                            "iv.ggtyler.dev"
                            "iv.nboeck.de"
                            "yewtu.be"
                        ];
                        minutesSaved = 31.89276535000001;
                        skipCount = 60;
                        defaultCategory = "chooseACategory";
                        segmentListDefaultTab = 0;
                        forceChannelCheck = false;
                        sponsorTimesContributed = 0;
                        submissionCountSinceCategories = 0;
                        showTimeWithSkips = true;
                        disableSkipping = false;
                        muteSegments = true;
                        fullVideoSegments = true;
                        fullVideoLabelsOnThumbnails = true;
                        manualSkipOnFullVideo = false;
                        trackViewCount = true;
                        trackViewCountInPrivate = true;
                        trackDownvotes = true;
                        trackDownvotesInPrivate = false;
                        dontShowNotice = false;
                        showUpcomingNotice = false;
                        noticeVisibilityMode = 3;
                        hideVideoPlayerControls = false;
                        hideInfoButtonPlayerControls = false;
                        hideDeleteButtonPlayerControls = false;
                        hideUploadButtonPlayerControls = false;
                        hideSkipButtonPlayerControls = false;
                        hideDiscordLaunches = 0;
                        hideDiscordLink = false;
                        supportInvidious = false;
                        serverAddress = "https://sponsor.ajay.app";
                        minDuration = 0;
                        skipNoticeDuration = 4;
                        audioNotificationOnSkip = false;
                        checkForUnlistedVideos = false;
                        testingServer = false;
                        ytInfoPermissionGranted = false;
                        allowExpirements = true;
                        showDonationLink = true;
                        showPopupDonationCount = 0;
                        showUpsells = true;
                        showNewFeaturePopups = true;
                        donateClicked = 0;
                        autoHideInfoButton = true;
                        autoSkipOnMusicVideos = false;
                        skipNonMusicOnlyOnYoutubeMusic = false;
                        scrollToEditTimeUpdate = false;
                        hookUpdate = false;
                        showChapterInfoMessage = true;
                        darkMode = true;
                        showCategoryGuidelines = true;
                        showCategoryWithoutPermission = false;
                        showSegmentNameInChapterBar = true;
                        showAutogeneratedChapters = true;
                        useVirtualTime = true;
                        showSegmentFailedToFetchWarning = true;
                        deArrowInstalled = true;
                        showDeArrowPromotion = true;
                        showDeArrowInSettings = true;
                        shownDeArrowPromotion = false;
                        cleanPopup = false;
                        hideSegmentCreationInPopup = false;
                        prideTheme = false;
                        categoryPillColors = {};
                        skipKeybind = {
                            key = "Enter";
                        };
                        skipToHighlightKeybind = {
                            key = "Enter";
                            ctrl = true;
                        };
                        startSponsorKeybind = {
                            key = ";";
                        };
                        submitKeybind = {
                            key = "'";
                        };
                        actuallySubmitKeybind = {
                            key = "'";
                            ctrl = true;
                        };
                        previewKeybind = {
                            key = ";";
                            ctrl = true;
                        };
                        nextChapterKeybind = {
                            key = "ArrowRight";
                            ctrl = true;
                        };
                        previousChapterKeybind = {
                            key = "ArrowLeft";
                            ctrl = true;
                        };
                        closeSkipNoticeKeybind = {
                            key = "Backspace";
                        };
                        downvoteKeybind = {
                            key = "h";
                            shift = true;
                        };
                        upvoteKeybind = {
                            key = "g";
                            shift = true;
                        };
                        payments = {
                            licenseKey = null;
                            lastCheck = 0;
                            lastFreeCheck = 0;
                            freeAccess = false;
                            chaptersAllowed = false;
                        };
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
                    };
                    
                    deArrow = {
                        showActivatedMessage = true;
                        enableExtensionKey = {
                            key = "e";
                            ctrl = true;
                            shift = true;
                            alt = true;
                        };
                        thumbnailReplacements = 1239;
                        freeAccessWaitingPeriod = 43200000;
                        showInfoAboutRandomThumbnails = false;
                        alreadyActivated = true;
                        userID = "@TODO: Secret here";
                        shouldCleanEmojis = true;
                        titleReplacements = 7850;
                        freeAccessRequestStart = 1766951178559;
                        freeTrialStart = 1766951456962;
                        onlyTitleCaseInEnglish = false;
                        licenseKey = "@TODO: Secret here";
                        showInfoAboutCasualMode = false;
                        freeActivation = false;
                        firefoxOldContentScriptRegistration = false;
                        freeTrialEnded = false;
                        formatCustomTitles = true;
                        showLiveCover = false;
                        titleFormatting = 2;
                        activated = true;
                        formatOriginalTitles = true;
                        openMenuKey = {
                            key = "d";
                            shift = true;
                        };
                        thumbnailFallback = 0;
                        replaceThumbnails = false;
                        actAsVip = true;
                        allowExpirements = true;
                        showDonationLink = true;
                        showUpsells = true;
                        donateClicked = 0;
                        darkMode = true;
                        invidiousInstances = [];
                        keepUnsubmitted = true;
                        keepUnsubmittedInPrivate = false;
                        thumbnailSaturationLevel = 100;
                        serverAddress = "https://sponsor.ajay.app";
                        thumbnailServerAddress = "https://dearrow-thumb.ajay.app";
                        fetchTimeout = 7000;
                        startLocalRenderTimeout = 2000;
                        renderTimeout = 25000;
                        thumbnailCacheUse = 2;
                        showGuidelineHelp = true;
                        thumbnailFallbackAutogenerated = 0;
                        extensionEnabled = true;
                        defaultToCustom = true;
                        alwaysShowShowOriginalButton = false;
                        showOriginalOnHover = false;
                        showOriginalOnHoverOfVideo = false;
                        showCustomOnHoverIfCasual = false;
                        importedConfig = false;
                        replaceTitles = true;
                        useCrowdsourcedTitles = true;
                        titleMaxLines = 3;
                        casualMode = false;
                        casualModeSettings = {
                            funny = 1;
                            creative = 1;
                            clever = 1;
                            descriptive = 1;
                            other = 1;
                        };
                        showOriginalThumbWhenCasual = false;
                        onlyShowCasualIconForCustom = false;
                        formatCasualTitles = true;
                        channelOverrides = {};
                        customConfigurations = {};
                        showIconForFormattedTitles = true;
                        countReplacements = true;
                        ignoreAbThumbnails = true;
                        ignoreTranslatedTitles = false;
                        hideDetailsWhileFetching = true;
                        firstThumbnailSubmitted = false;
                        freeTrialDuration = 21600000;
                        lastIncognitoStatus = false;
                        confirmGuidelinesCount = 0;
                        lastGuidelinesConfirmation = 0;
                        vip = false;
                    };
                    
                    ytTweaks = {
                        ambientMode = true;
                        autoSidebarComments = false;
                        changeSpeedOnScroll = false;
                        compactButtons = true;
                        compactLeftSidebar = false;
                        decreaseFontSize = false;
                        dimWatchVideos = "50-100%";
                        dimWatchVideos2 = "50-100%";
                        dimWatchVideos3 = "50-100%";
                        dimWatchVideos4 = "50-100%";
                        dimWatchVideos5 = "50-100%";
                        disableAutoPause = true;
                        disableNumHotkeys = true;
                        dnhTopRow = "1-9";
                        fixChannelLinks = true;
                        ftmAutoHideHeader = false;
                        fullscreenTheaterMode = true;
                        gridFix = true;
                        gridSearchResults = true;
                        hideClipButton = true;
                        hideControlsOnPause = true;
                        hideDownloadButton = true;
                        hideEndCards = "hide";
                        hideExplore = true;
                        hideLatestYouTubePosts = true;
                        hideLiveStreams = "both";
                        hideLiveStreams2 = "both";
                        hideLiveStreams3 = "both";
                        hideLiveStreams4 = "both";
                        hideMixes = true;
                        hideMixes2 = true;
                        hideMixes3 = true;
                        hideMoreFromYt = true;
                        hideProfilePictures = true;
                        hideRecommendationBar = true;
                        hideRightSidebar = true;
                        hideSearchResults = true;
                        hideShareButton = true;
                        hideShorts = true;
                        hideShorts2 = true;
                        hideShorts3 = true;
                        hideShorts4 = true;
                        hideShorts5 = true;
                        hideShortsButton = true;
                        hideThanksButton = true;
                        hideUpcoming = true;
                        hideWatchVideos = "95-100%";
                        hideWatchVideos3 = "95-100%";
                        hideWatchVideos4 = "95-100%";
                        maxNumOfColumns = "5";
                        maxNumOfColumns2 = "1";
                        moreAnimations = false;
                        pinVideoOnScroll = true;
                        pinnedVideoPosition = "Top right";
                        sResultsInNewTab = true;
                        scrollUpBtnColor = "hsla(0, 0%, 0%, 0)";
                        scrollUpBtnRoundCorners = 20;
                        scrollUpBtnSvgColor = "hsla(0, 0%, 100%, 1)";
                        scrollUpBtnWidth = 44;
                        scrollUpButton = "On the left";
                        showFullVideoTitles = true;
                        sidebarComments = false;
                        snapshotFormat = "png";
                        timeFormat = "left";
                        vfBlur = 2;
                        vfOpacity = 0.75;
                        videoFocus = true;
                        videoQuality = "hd1440";
                        videoRemTime = true;
                        videoSnapshot = true;
                        videosAsDefaultTab = true;
                        videosPerRow = true;
                        volumeBoost = false;
                        vqFallback = "lowest";
                        watchVideoOpacity = 0.33;
                        watchVideoOpacity2 = 0.33;
                        watchVideoOpacity3 = 0.33;
                        watchVideoOpacity4 = 0.33;
                        watchVideoOpacity5 = 0.33;
                        whereToShowTime = "player";
                    };
                in
                {
                    "./sponsorblock.json".text = builtins.toJSON sponsorBlock;
                    "./dearrow.json".text = builtins.toJSON deArrow;
                    "./yt-tweaks.json".text = builtins.toJSON ytTweaks;
                };
            };
        };
    };
}