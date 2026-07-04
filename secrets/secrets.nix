let
    hostDirectory = ../hosts;
    
    # Import every host's _host.nix file 
    hostNames = builtins.attrNames (builtins.readDir hostDirectory);
    hosts = map (host: import (hostDirectory + "/${host}/_host.nix")) hostNames;
    
    # Every .age file from any of the hosts
    allAgeFiles = builtins.concatMap (host: host.ageFiles) hosts;
    cleanedAgeFiles = builtins.attrNames (builtins.listToAttrs(
        map (name: { inherit name; value = null; }) allAgeFiles
    ));
    
    # Every public key from the hosts configuration
    publicKeys = name: builtins.concatMap (host: if builtins.elem name host.ageFiles then host.publicKeys else [ ]) hosts;
in
    # agenix -e {name}.age
    builtins.listToAttrs ( map ( 
        name: { inherit name; value.publicKeys = publicKeys name; }
    ) cleanedAgeFiles)
    
    
# @TODO: Redo this