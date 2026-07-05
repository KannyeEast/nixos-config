flake := justfile_directory()
host := `hostname`

# Overview
default:
    @just --list

# Rebuild switch
switch:
    nh os switch {{flake}} -H {{host}}

# Test the config in a VM
test:
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