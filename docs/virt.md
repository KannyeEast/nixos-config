# virt

Addon, desktop only. Two halves: full guests under libvirt, and throwaway
containers under rootless docker.

## Guests

libvirt/qemu with virt-manager. Aimed at one long-lived Windows guest for
software that does not run on Linux.

| Setting | Value |
|---|---|
| `onBoot` | `ignore`; guests start by hand |
| `onShutdown` | `shutdown` |
| `swtpm` | on |
| `runAsRoot` | `false`; qemu runs as `qemu-libvirtd` |
| `vhostUserPackages` | `virtiofsd`, for the shared folder |
| `LIBVIRT_DEFAULT_URI` | `qemu:///system` |
| firewall | `virbr0` trusted; guests get a DHCP lease |

Paths:

| Path | Holds |
|---|---|
| `/var/lib/libvirt` | disk images and nvram; persisted |
| `/var/lib/libvirt/images` | created with `+C` (nodatacow) |
| `~/vm` | host side of the virtiofs share |

`+C` is inherited by files created afterwards and does nothing to files that
already exist. An image made before the rule ran stays CoW. Check with
`lsattr`; fix by copying the file.

qemu's OVMF images, including the secboot variant, are registered with libvirt
by default. Secure boot needs no option.

Under `runAsRoot = false`, qemu cannot traverse a `0700` home. Install media
belongs in `/var/lib/libvirt/images`, not `~`. virtiofsd passes an fd and is
unaffected.

### Creating a Windows guest

Fetch `virtio-win.iso` into `/var/lib/libvirt/images` first. `pkgs.virtio-win`
ships the extracted tree, not a mountable image, and Windows setup loads the
disk driver from a CD.

In virt-manager, **Customize configuration before install**, then:

1. Firmware → `edk2-x86_64-secure-code.fd`.
2. CPUs → model `host-passthrough`.
3. CPUs → Topology → **1 socket**, N cores. Windows licences by socket and
   ignores the rest.
4. Disk → bus `VirtIO`, cache `writeback`, IO `threads`, discard `unmap`.
5. Add Hardware → TPM → emulated, 2.0.
6. Add Hardware → Storage → CDROM → `virtio-win.iso`.
7. Display `Spice server`, video QXL, channel `com.redhat.spice.0`.
8. Add Hardware → Filesystem → driver `virtiofs`, source `~/vm`, target
   `vmshare`.

At the disk-selection screen, **Load driver** → `viostor\w11\amd64`.

Afterwards, in the guest: run `virtio-win-guest-tools.exe` from the same CD
(drivers, guest agent, SPICE agent, WinFsp), set **VirtIO-FS Service** to
automatic, and `powercfg /h off`.

### Constraints

**A guest with a virtiofs share is never saved.** `vhost-user-fs` does not
serialise its backend. A managed save produces a state file that cannot be
restored, and the guest refuses to start until it is discarded with
`virsh managedsave-remove`. `onShutdown` is `shutdown`. Snapshots of a running
guest include RAM; snapshot with the guest powered off.

**Internal snapshots need a qcow2 nvram.** libvirt's default varstore is raw
and `snapshot-create-as` refuses it. Convert it with `qemu-img convert` and set
`<nvram format='qcow2'>` in the domain.

**Garbage collection can break a guest.** The OVMF firmware path in the domain
XML is a nix store path. `nix-collect-garbage` can remove it, and the guest
fails to start until the path is updated.

**`virsh` needs a login shell.** `LIBVIRT_DEFAULT_URI` arrives through
`environment.sessionVariables`, which is read at login. Without it `virsh`
talks to `qemu:///session` and reports an empty list.

## Containers

Rootless docker. Membership of the `docker` group is equivalent to root; the
daemon bind-mounts any path on request. `virtualisation.docker.enable` is
`mkForce false`.

| Piece | Value |
|---|---|
| daemon | `systemd.user.services.docker` |
| socket | `$XDG_RUNTIME_DIR/docker.sock`, exported as `DOCKER_HOST` |
| storage | `~/.local/share/docker`, inside persisted home |
| compose | `pkgs.docker-compose` |

`DOCKER_HOST` comes from `environment.extraInit`. A shell started before the
switch, or a terminal inheriting such a session, does not have it. A fresh
login fixes it.

### Pruning

`virtualisation.docker.autoPrune` builds its service inside `mkIf` on the
rootful daemon and produces nothing here. `containers.nix` mirrors that unit
into the user manager and reads the same `autoPrune.*` options, so the schedule
and flags are configured in one place.

`docker system prune -f` removes stopped containers, dangling layers, unused
networks and build cache. Tagged images need `-a`, by hand.


### Rootless limits

- No host ports below 1024.
- Bind-mounted files appear owned by `root` inside the container; writes land
  as the user on the host.
- No meaningful `--privileged`, no touching host network interfaces.
- Docker-in-docker and some storage drivers do not work.