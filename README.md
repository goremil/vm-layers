# vm-layers

Layered QEMU virtual machines for NixOS hosts: a shared lifecycle core, Windows and NixOS guest types, and overlays for each purpose.

Status: early. The layers and the command contract are decided ([ADR 0002](docs/adr/0002-layers-and-core-contract.md)); NixOS guests use NixOS's own VM mechanisms plus the `pc` module ([ADR 0003](docs/adr/0003-nixos-guests-on-nixos-mechanisms.md)). The `pc` module works; the core and `winvm` are still to come.

## Use

`pc` makes a NixOS guest boot like a modern PC: UEFI, Secure Boot (lanzaboote, with keys the guest generates and enrols), a TPM2, and a LUKS2 volume the TPM2 unlocks once Secure Boot is on. The disk layout is yours, as disko devices:

```nix
# flake.nix
inputs.vm-layers.url = "github:goremil/vm-layers";

nixpkgs.lib.nixosSystem {
  modules = [
    lanzaboote.nixosModules.lanzaboote            # `pc` needs both beside it
    disko.nixosModules.disko
    vm-layers.nixosModules.pc
    ./disko.nix                                   # one LUKS2 volume, `cryptroot` by default
    { pc.luks.passwordFile = ./test-passphrase; } # the passphrase disko formats it with
  ];
}
```

The disk image is `system.build.diskoImages`; `system.build.pcVm` runs the guest from it, on an overlay in the working directory that keeps its state between runs. Point `NIX_SWTPM_DIR` at a short path, such as one under `$XDG_RUNTIME_DIR`: swtpm refuses a Unix socket path over about 108 characters, and its default is the working directory. `nixosModules.testbed` is a neutral example with a typical layout, and `nixosConfigurations.testbed` builds it.

See [AGENTS.md](AGENTS.md) for how to work in this repository.

## Development

```sh
nix develop             # every check tool; enables the git hooks
repo-check              # every check, one report; -v for each output
nix fmt                 # treefmt: nixfmt, shfmt, and ruff with the python profile
nix flake update base   # the next version of the managed set
nix build -L .#tests.pc   # VM test, needs KVM; kept out of the checks
```

## Licence

Code, build definitions and configuration are under GPL-3.0-only, documentation under CC-BY-SA-4.0. `REUSE.toml` maps each path to its licence, and `reuse lint` checks it.
