# 0002. Layers and the core contract

- Status: Accepted
- Date: 2026-10-31

## Context

A NixOS host runs virtual machines for several purposes: a Windows guest for general use, a Windows guest that
records a vendor application talking to a USB device, a NixOS guest with UEFI, Secure Boot, TPM2, LUKS and
impermanence for testing. Each was built on its own, with general mechanics, personal data and purpose-specific
settings in one place.

Windows and NixOS guests are built in different ways. Windows is installed once, then its state is declared and its
hardware identity kept fixed, so that its licence stays activated. NixOS is built from a flake each time, and the
nixpkgs `qemu-vm` module already provides UEFI, Secure Boot (`virtualisation.useSecureBoot`) and a TPM
(`virtualisation.tpm.enable`). What both share is the lifecycle around QEMU, not the guest's configuration.

## Decision

### Layers

| Layer | Holds | Where |
| --- | --- | --- |
| core | the command contract below and a library for the lifecycle | here |
| guest type | `winvm` (Windows, on Quickemu) and `nixosvm` (NixOS, on `qemu-vm`) | here |
| purpose overlay | a profile for one use, such as a test bed or a recording guest | here when it is general, else in the repository that uses it |
| host overlay | hardware identity, secrets, the USB allow list, facts about one machine | the host's own configuration, never here |

Dependencies go one way: a host configuration uses this repository, and nothing here names a host or a private
repository.

### The core does not start QEMU

Each guest type has its own launcher: Quickemu for `winvm`, the `run-*-vm` script of the `qemu-vm` module for
`nixosvm`. The core is a bash library (`writeShellApplication`, checked by shellcheck) that the commands of every
guest type share: the watcher, USB lending, `put` and `get`, the state directory and the lock.

### One command per guest type

`winvm` and `nixosvm` are separate commands, with one form: `<command> [--profile NAME] COMMAND`. Without
`--profile`, the running profile, else the default one.

| Command | Does |
| --- | --- |
| `start [--scratch]` | start the guest, or reopen its viewer; `--scratch` keeps no disk write (QEMU's `-snapshot`) |
| `stop [--wait]` | ACPI shutdown; `--wait` returns once QEMU has quit |
| `status` | whether the guest runs, and which profile |
| `info` | the guest system and its version, one line |
| `usb list`, `usb attach NAME`, `usb detach NAME` | the devices that may be lent, lend one to the guest, give it back |
| `put FILE... --to DIR [--from DIR]` | copy into the guest folder `DIR`; no default folder |
| `get PATH... --to DIR [--from DIR]` | copy from the guest into the host folder `DIR`; no default folder |
| `ssh [args...]` | a shell in the guest |
| `conf` | the path of the VM definition |

Each guest type adds its own commands, for example `install`, `check` and `debloat` for `winvm`, and `build` and
`check` for `nixosvm`.

### What the core guarantees

- One VM at a time within an exclusive group, such as all profiles that share one hardware identity.
- A state directory `$XDG_DATA_HOME/<command>/<profile>`, created with `chattr +C` (no copy-on-write for disk
  images on btrfs).
- A watcher that closes the viewer and quits QEMU once the guest is off.
- `-machine dump-guest-core=off`, so guest memory stays out of core dumps.
- No shared folders: files cross one at a time through `put` and `get`, over SSH with the VM's own key.
- USB only through a root helper that grants an ACL on one device node, for devices on an allow list. The helper is
  here; the list belongs to the host overlay.

## Consequences

- A tool that drives a guest, such as a recording script, needs only the common commands, whatever the guest type.
- The Windows guest tool moves here from a host configuration in its own step, with its hardware identity and
  secrets left behind in a host overlay; its licence activation is checked before and after.
- Not yet checked: whether the `qemu-vm` run script takes a QEMU monitor socket the way Quickemu does, which the
  `status`, `stop` and USB commands use. It probably does, through `virtualisation.qemu.options`.
