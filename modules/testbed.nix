# Purpose overlay `testbed`: a neutral guest for testing NixOS configurations
# against the hardware a modern PC has, on top of `pc`. Its disk has a typical
# layout: an ESP, then LUKS2 with btrfs subvolumes for the root, its blank
# snapshot, the Nix store, persistent state, logs and homes.
{ config, pkgs, ... }:
let
  btrfsOptions = [
    "compress=zstd"
    "noatime"
  ];
in
{
  networking.hostName = "testbed";

  # Known on purpose: the volume is a test guest's, and its passphrase stays as
  # the fallback key slot beside the TPM2.
  pc.luks.passwordFile = pkgs.writeText "testbed-luks-passphrase" "testbed";

  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/vda";
    imageSize = "8G";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [
              "fmask=0077"
              "dmask=0077"
            ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            passwordFile = "${config.pc.luks.passwordFile}";
            settings.allowDiscards = true;
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "@root" = {
                  mountpoint = "/";
                  mountOptions = btrfsOptions;
                };
                # Empty, for a root that rolls back to it on every boot.
                "@root-blank" = { };
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = btrfsOptions;
                };
                "@persist" = {
                  mountpoint = "/persist";
                  mountOptions = btrfsOptions;
                };
                "@log" = {
                  mountpoint = "/var/log";
                  mountOptions = btrfsOptions;
                };
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = btrfsOptions;
                };
              };
            };
          };
        };
      };
    };
  };

  fileSystems."/persist".neededForBoot = true;

  environment.systemPackages = [
    pkgs.sbctl
    pkgs.tpm2-tools
  ];

  system.stateVersion = "26.11";
}
