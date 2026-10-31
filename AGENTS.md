# AGENTS.md

Instructions for any agent, human or AI, working in this repository.

## What this repository is

Layered QEMU virtual machines for NixOS hosts: a shared lifecycle core, Windows and NixOS guest types, and overlays for each purpose. See [README.md](README.md).

## Rules

- The rule core of `setup-base` applies; a departure from it is recorded under "Deviations" below.
- This repository is public. Nothing personal goes in: no names of hosts, people or private repositories, no paths into a user's home directory.
- `repo-check` passes before a commit; the pre-commit hook runs it.

## Layout

| Path | Content |
| --- | --- |
| `docs/adr/` | Architecture decisions |
| `flake.nix` | Dev shell, `formatter` and `checks` from `setup-base`; `nixosModules`, `nixosConfigurations.testbed`, `legacyPackages.<system>.tests` |
| `modules/` | NixOS modules: `pc.nix` and `pc-qemu.nix` (ADR 0003), `testbed.nix` (purpose overlay) |
| `tests/` | NixOS VM tests, run with `nix build .#tests.<name>`; not in `checks`, they take minutes and need KVM |
| `.envrc` | direnv enters the dev shell (`use flake`) |
| `.githooks/` | pre-commit (`repo-check`), commit-msg and pre-push (signed and squashed commits, R-git-07), in the dev shell |
| `.markdownlint-cli2.jsonc` | Lint profile, linked by the dev shell; untracked |
| `cspell.config.yaml`, `.cspell/` | Spell-check settings and word lists of this repository; `oxford.yaml`, `oxford-ize.txt` and `nix-words.txt` are the managed profile, replaced by `copier update` |
| `REUSE.toml`, `LICENSES/` | Licence of each path |
| `.github/workflows/` | CI: `repo-check -v` on every push |
| `.copier-answers.yml` | Template answers for `copier update`; not edited |

## Deviations

Departures from the `setup-base` rule core, one row each (R-rules-03). A deviation not listed here is a mistake, not a decision; `repo-check` checks each row and asks for the departures it can see.

| Rule | What differs | Reason | Since | Decision |
| --- | --- | --- | --- | --- |
