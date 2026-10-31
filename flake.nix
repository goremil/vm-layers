{
  description = "Layered QEMU virtual machines for NixOS hosts: a shared lifecycle core, Windows and NixOS guest types, and overlays for each purpose.";

  # The managed set: check tools, repo-check, hooks' commands, formatter and
  # checks. `nix flake update base` brings a new version; flake.lock pins it.
  inputs.base.url = "git+https://github.com/goremil/setup-base";

  outputs = { self, base }: base.lib.mkRepo { inherit self; };
}
