flake := justfile_directory()

# Overview
default:
    @just --list

# Rebuild switch
switch HOSTNAME='hostname':
    git add --intent-to-add . && \
    nh os switch {{flake}} -H {{HOSTNAME}}

# Test the config in a VM
test HOSTNAME='hostname':
    nixos-rebuild build-vm --flake {{flake}}#{{HOSTNAME}}
    ./result/bin/run-{{HOSTNAME}}-vm

# Check if flake evaluates
check:
    nix flake check {{flake}}

# Clear GC    
clean:
    nh clean all
    
# Clean code
fmt:
    cd {{flake}} && find . -name '*.nix' -exec nixfmt {} + && deadnix .
    

# Utilize [private] and [group] to make bundeled commands

[group("git")]
stage:
    git stage .
    
[group("git")]
commit MESSAGE:
    git commit