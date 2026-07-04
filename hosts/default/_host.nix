{
    # System 
    hostname = "default";
    system = "x86_64-linux";

    # Secrets 
    ## Which ssh keys can decrypt which .age file
    publicKeys = [ 
        "ssh-ed25519 <hostKey> root@host1"
        "ssh-ed25519 <userKey> you@user1"
    ];
    ageFiles = [
        "secret1.age"
        "secret2.age"
    ];
    
    # Optional
    ## https://github.com/NixOS/nixos-hardware
    hardwareModel = null;
}