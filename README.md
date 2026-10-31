# vm-layers

Layered QEMU virtual machines for NixOS hosts: a shared lifecycle core, Windows and NixOS guest types, and overlays for each purpose.

Status: design. The layers and the command contract are decided ([ADR 0002](docs/adr/0002-layers-and-core-contract.md)); no code yet.

See [AGENTS.md](AGENTS.md) for how to work in this repository.

## Development

```sh
nix develop             # every check tool; enables the git hooks
repo-check              # every check, one report; -v for each output
nix fmt                 # treefmt: nixfmt, shfmt, and ruff with the python profile
nix flake update base   # the next version of the managed set
```

## Licence

Code, build definitions and configuration are under GPL-3.0-only, documentation under CC-BY-SA-4.0. `REUSE.toml` maps each path to its licence, and `reuse lint` checks it.
