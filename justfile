flake := justfile_directory()

# Overview
list:
    @just --list

# Rebuild switch
switch host='hostname':
    nh os switch {{flake}} -H {{host}}

# Test the config in a VM
test host='hostname':
    nixos-rebuild build-vm --flake {{flake}}#{{host}}
    ./result/bin/run-{{host}}-vm

# Check if flake evaluates
check:
    nix flake check {{flake}}

# Clear GC    
clean:
    nh clean all
    
# Clean code
fmt:
    cd {{flake}} && find . -name '*.nix' -exec nixfmt {} + && deadnix .