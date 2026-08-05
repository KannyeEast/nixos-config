{ ... }:
{
  flake.modules.homeManager.passwords =
    { ... }:
    {
      config = {      
        xdg.autostart.enable = true;
        programs.keepassxc = {
          autostart = true;
          enable = true;
          settings = {
            Browser.Enabled = true;
            Browser.BestMatchOnly = true;
            Browser.SearchInAllDatabases = true;
            Browser.UnlockDatabase = true;
            Browser.MatchUrlScheme = true;
            
            SSHAgent.Enabled = true;
            SSHAgent.UseOpenSSH = true;
            
            FdoSecrets.Enabled = true;
          };
        };
      };
    };
}
