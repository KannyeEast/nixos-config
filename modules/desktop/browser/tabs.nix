{ ... }:
{
    flake.modules.homeManager.browserTabs = { ... }:
    let

        bookmarks = [
            {
                name = "Streaming Sites";
                bookmarks = [
                    {   
                        # @TODO: Zen needs DRM support for this >> Maybe not on linux actually
                        name = "F1TV";
                        tags = [ "streaming" ];
                        url = "https://f1tv.formula1.com/";
                    }
                    {
                        name = "F1";
                        tags = [ "streaming" ];
                        url = "https://f1live.dpdns.org/1";
                    }
                    {
                        name = "Football";
                        tags = [ "streaming" ];
                        url = "https://streamed.pk/";
                    }
                ];
            }
            {
                name = "Shortcuts";
                bookmarks = [
                    {
                        name = "YouTube";
                        url = "https://www.youtube.com/";
                    }
                    {
                        name = "Reddit";
                        url = "https://www.reddit.com/";
                    }
                    {
                        name = "Regex";
                        url = "https://regex101.com/";
                    }
                ];
            }
        ];
                        
        pins = {
            "Proton" = {
                id = "986ce577-0407-46b0-90cb-d2ad8dba406c";
                url = "https://account.proton.me/apps";
                position = 1;
                isEssential = true;
            };
            "SimpleLogin" = {
                id = "8e9537c6-400d-4d3f-9dc8-724c4c76cb07";
                url = "https://app.simplelogin.io/dashboard/";
                position = 2;
                isEssential = true;
            };
            
            "Documents" = {
                id = "27b7c2ce-6856-43c3-b996-b99d4a8b8578";
                url = "https://docs.proton.me/";
                position = 101;
                workspace = spaces."Entertainment".id;
            };
            
            "GitHub" = {
                id = "fcc811cc-1389-4b0f-8384-949da46ad442";
                url = "https://github.com/notifications";
                position = 201;
                workspace = spaces."Development".id;
            };
            
            "Server" = {
                id = "e0f080f0-6cab-41d5-b416-cc07d318b969";
                position = 300;
                workspace = spaces."Personal Projects".id;
                isGroup = true;
                isFolderCollapsed = true;
                editedTitle = true;
                folderIcon = "chrome://browser/skin/zen-icons/selectable/folder.svg";
            };
            "FRITZ!Box" = {
                id = "36a3dbb0-447f-4446-8dd8-df1b169cbc12";
                url = "http://192.168.178.1/";
                position = 301;
                workspace = spaces."Personal Projects".id;
                folderParentId = pins."Server".id;
            };
            "Cloudflare Dashboard" = {
                id = "9fb4ee37-0150-4532-ad02-f981f102f16a";
                url = "https://dash.cloudflare.com/";
                position = 302;
                workspace = spaces."Personal Projects".id;
                folderParentId = pins."Server".id;
            };
        };
        
        spaces = {
            "Entertainment" = {
                id = "a8fde799-77d2-4b1c-8c83-37dce87d30be";
                position = 1000;
            };
            "Development" = {
                id = "779e73b8-5f81-4538-9d92-e7da96824c56";
                position = 2000;
            };
            "Personal Projects" = {
                id = "6698068a-20c7-436b-9351-b024cde94686";
                position = 3000;
            };
        };
    in
    {   
        config = {
            programs.zen-browser.profiles.default = {
                bookmarks.force = true;
                bookmarks.settings = bookmarks;

                pinsForce = true;
                pins = pins;

                spacesForce = true;
                spaces = spaces;
            };
        };
    };
}