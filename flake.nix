{
  description = "Layered QEMU virtual machines for NixOS hosts: a shared lifecycle core, Windows and NixOS guest types, and overlays for each purpose.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # The managed set: check tools, repo-check, hooks' commands, formatter and
    # checks. `nix flake update base` brings a new version; flake.lock pins it.
    base = {
      url = "git+https://github.com/goremil/setup-base";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Secure Boot for the `pc` module: signed boot files and keys generated and
    # enrolled by the guest itself.
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # The `pc` disk: partitions, LUKS and btrfs, built into an image.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      base,
      lanzaboote,
      disko,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      repo = base.lib.mkRepo { inherit self; };
      # `pc` with the modules it needs, for the test bed and the tests.
      pcWithDependencies = {
        imports = [
          lanzaboote.nixosModules.lanzaboote
          disko.nixosModules.disko
          self.nixosModules.pc
        ];
      };
    in
    repo
    // {
      nixosModules = {
        # A NixOS guest booted the way a modern PC boots it (ADR 0003). It needs
        # lanzaboote's and disko's modules beside it; a configuration that
        # imports them already must not get them twice, so they stay out.
        pc = ./modules/pc.nix;
        # Purpose overlay: a neutral test bed on top of `pc`.
        testbed = ./modules/testbed.nix;
      };

      nixosConfigurations.testbed = nixpkgs.lib.nixosSystem {
        modules = [
          pcWithDependencies
          self.nixosModules.testbed
          { nixpkgs.hostPlatform = system; }
        ];
      };

      # VM tests take minutes and need KVM, so they stay out of `checks`, which
      # the pre-commit hook builds: `nix build .#tests.pc`.
      legacyPackages.${system}.tests = {
        pc = pkgs.testers.runNixOSTest {
          imports = [ ./tests/pc.nix ];
          extraBaseModules.imports = [ pcWithDependencies ];
        };
      };
    };
}
