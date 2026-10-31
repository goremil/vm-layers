# vm-layers

Layered QEMU virtual machines for NixOS hosts: a shared lifecycle core, Windows and NixOS guest types, and overlays for each purpose.

Status: early. The layers and the command contract are decided ([ADR 0002](docs/adr/0002-layers-and-core-contract.md)); NixOS guests use NixOS's own VM mechanisms plus the `pc` module ([ADR 0003](docs/adr/0003-nixos-guests-on-nixos-mechanisms.md)). The `pc` module and `winvm` work; the shared core is still to come, and `winvm` still carries its own lifecycle.

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

`winvm` is a Windows 11 Pro guest under Quickemu, a home-manager module, with the `winvm` command (`winvm` alone lists its subcommands): an unattended install, Secure Boot and a TPM 2.0, a fixed hardware identity so the licence survives reinstalls, profiles that share that identity with one disk each, SSH into the guest, and a declared guest state applied from a script you supply. Your host overlay sets the values; nothing personal is built in:

```nix
# home-manager
imports = [ vm-layers.homeModules.winvm ];
programs.winvm = {
  enable = true;
  identity = { uuid = "…"; serial = "…"; mac = "52:54:00:…"; };   # generate once, never change
  smbios = { biosVersion = "…"; biosDate = "MM/DD/YYYY"; product = "…"; };
  user.name = "…";
  computerName = "…";
  locale = { ui = "en-GB"; input = "0809:00000809"; timeZone = "GMT Standard Time"; };
  productKeyFile = "/run/user/1000/secrets/windows-product-key";  # read at run time, for example from sops-nix
  passwordFile = "…";
  tpmStateFile = "…";                                               # base64 swtpm state, restored when no profile has one
  profiles = { default = { }; lab = { autoLogon = true; note = "tests only"; }; };
  taskmgrSettings = ./taskmgr.json;
  debloatScript = ./debloat.ps1;                                    # -Mode specialize|apply|check|clean
};
```

USB devices are lent to the guest through `nixosModules.winvm-usb`, a root helper that sets an ACL on one device node for devices on an allow list: `programs.winvm.usb = { enable = true; user = "…"; allowed.stick = "0781:5581"; };`.

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
