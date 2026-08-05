{ lib, ... }:
let
in
{
  flake.modules.homeManager.passwords =
    { ... }:
    {
      config = {
        programs.keepassxc = {
          autostart = true;
          enable = true;
          settings = {
            General = {
              AutoTypeDelay = 15;
              AutoTypeStartDelay = 150;
              BackupBeforeSave = true;
              GlobalAutoTypeKey = 65;
              GlobalAutoTypeModifiers = 335544320;
              URLDoubleClickAction = 1;
              UpdateCheckMessageShown = true;
            };
            
            Browser = {
                Enabled = true;
                BestMatchOnly = true;
                SearchInAllDatabases = true;
            };
            
            GUI = {
              ApplicationTheme = "auto";
              ColorPasswords = true;
              MonospaceNotes = true;
            };
            
            SSHAgent = {
              Enabled = true;
              UseOpenSSH = true;
              AuthSockOverride = "";
              SecurityKeyProviderOverride = "";
            };
            
            FdoSecrets = {
              Enabled = true;
            };
            
            PasswordGenerator = {
                LowerCase = true;
                UpperCase = true;
                Numbers = true;
                
                AdvancedMode = true;
                SpecialChars = false;
                AdditionalChars = ''
                  !"#$%&()*+,-./:;<=>?@[\]_{|}~
                '';
                ExcludedChars = ''
                  °`´§'^
                '';
                
                Length = 20;
            };
          };
        };
      };
    };
}
