# 0003. NixOS guests on NixOS's own mechanisms, plus a `pc` module

- Status: Accepted
- Date: 2026-10-31
- Supersedes: the `nixosvm` guest type of [0002](0002-layers-and-core-contract.md)

## Context

[0002](0002-layers-and-core-contract.md) gives NixOS guests a guest type of their own, `nixosvm`, with a command on the
shared core. Trying it showed that NixOS and its ecosystem already cover most of what a NixOS guest needs:

| Need | Already there |
| --- | --- |
| a quick VM of any configuration | `system.build.vm` (`nixos-rebuild build-vm`): direct boot, the host's store, seconds to start |
| automated tests in a repository | `runNixOSTest`: several VMs, a TPM (`virtualisation.tpm`), UEFI (`virtualisation.useEFIBoot`) |
| a host's configuration with its real disk layout | disko's `system.build.vmWithDisko`: the host's partitions and LUKS, built into an image |

What is missing is the glue that makes a guest boot like a real PC: Secure Boot keys enrolled in the firmware, a LUKS
volume bound to the TPM2, and a boot through the firmware from a disk image rather than a direct kernel boot. That
glue is about a hundred lines, and both a test bed and a host's own VM test want the same lines.

Two facts from 0002 no longer hold on nixpkgs unstable, which this repository follows:

- `virtualisation.useSecureBoot` was removed; the default OVMF always supports Secure Boot.
- The `qemu-vm` run script does take a QEMU monitor socket: it passes `virtualisation.qemu.options`, then
  `$QEMU_OPTS`, then its own arguments to QEMU.

## Decision

- NixOS guests use NixOS's own mechanisms: `system.build.vm`, `runNixOSTest` and disko's images. There is no
  `nixosvm` command, and the core serves `winvm` only.
- This repository publishes one NixOS module, `pc`, that makes any of them boot like a real PC: UEFI and
  systemd-boot through lanzaboote, Secure Boot keys the guest generates and enrols itself, a TPM2, and a LUKS2 volume
  bound to the TPM2 (PCR 7) once Secure Boot is on. The disk layout comes from the user of the module, as disko
  devices, so a host's VM test keeps its own layout.
- The `testbed` overlay stays as a neutral example: `pc` with a typical layout (an ESP, then LUKS2 with btrfs
  subvolumes).

## Consequences

- A host configuration gets Secure Boot and a TPM2 in its VM test by importing `pc` next to its own disko layout.
- A NixOS guest that is interactive and long-lived, with USB lending or `put` and `get`, has no home here yet. If one
  is needed, a `nixosvm` command on the core is reconsidered then.
