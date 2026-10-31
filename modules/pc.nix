# Module `pc`: a NixOS guest that boots the way a modern PC boots it, through
# UEFI and systemd-boot (lanzaboote), with Secure Boot keys the guest generates
# and enrols itself, a TPM2 (swtpm), and its LUKS2 volumes bound to the TPM2
# once Secure Boot is on (ADR 0003).
#
# The disk layout is the user's, as disko devices on one disk whose LUKS2
# volumes are named in `pc.luks.volumes`; disko builds it into an image
# (`system.build.diskoImages`). `system.build.pcVm` runs the guest from it.
#
# Boots, in order:
#   1. passphrase; the guest generates its Secure Boot keys, re-signs the ESP
#      and writes the keys' authenticated variables to it;
#   2. passphrase; systemd-boot enrols the keys, Secure Boot is on in user mode,
#      and the guest binds the LUKS volumes to the TPM2 (PCR 7);
#   3. and later: the TPM2 unlocks the volumes, no passphrase.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.pc;
  luksDevices = map (name: config.boot.initrd.luks.devices.${name}.device) cfg.luks.volumes;
  vm = config.virtualisation.vmVariant.system.build;
  disk = lib.head (lib.attrValues config.disko.devices.disk);
in
{
  options.pc.luks = {
    volumes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "cryptroot" ];
      description = "Names of the LUKS2 volumes the TPM2 unlocks, as in `boot.initrd.luks.devices`.";
    };
    passwordFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        File with the volumes' passphrase, the one disko formats them with. The
        guest uses it once per volume, to add the TPM2 key slot; the passphrase
        slot stays.
      '';
    };
  };

  config = {
    boot = {
      loader.efi.canTouchEfiVariables = true;
      lanzaboote = {
        enable = true;
        pkiBundle = "/var/lib/sbctl";
        autoGenerateKeys.enable = true;
        autoEnrollKeys.enable = true;
      };
      # systemd-cryptsetup in the initrd tries the TPM2 token before asking.
      initrd.luks.devices = lib.genAttrs cfg.luks.volumes (_: {
        crypttabExtraOpts = [ "tpm2-device=auto" ];
      });
    };

    disko.imageBuilder.imageFormat = "qcow2";

    # disko's image builder installs the boot loader through it; the NixOS test
    # base turns it off by default.
    system.switch.enable = true;

    # Bind the volumes to the TPM2 once Secure Boot is on, so that PCR 7 holds
    # the enrolled keys; before that its value would change on the next boot.
    systemd.services.pc-tpm2-enroll = {
      description = "Bind the LUKS volumes to the TPM2";
      wantedBy = [ "multi-user.target" ];
      unitConfig.ConditionSecurity = "uefi-secureboot";
      path = [
        config.systemd.package
        pkgs.cryptsetup
        pkgs.jq
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = lib.concatMapStrings (device: ''
        if ! cryptsetup luksDump --dump-json-metadata ${device} |
          jq -e '.tokens[] | select(.type == "systemd-tpm2")' > /dev/null; then
          systemd-cryptenroll ${device} \
            --unlock-key-file=${cfg.luks.passwordFile} \
            --tpm2-device=auto \
            --tpm2-pcrs=7
        fi
      '') luksDevices;
    };

    # Runs the guest from its disk image, on a copy-on-write overlay that
    # keeps its state between runs: `$NIX_DISK_IMAGE`, else
    # `<name>.qcow2` in the working directory. Its UEFI variables and TPM
    # state land next to it, as the `qemu-vm` run script places them.
    system.build.pcVm = pkgs.writeShellScriptBin "run-${config.system.name}-pc" ''
      set -eu
      export NIX_DISK_IMAGE="''${NIX_DISK_IMAGE:-$PWD/${config.system.name}.qcow2}"
      if [ ! -e "$NIX_DISK_IMAGE" ]; then
        ${lib.getExe' pkgs.qemu-utils "qemu-img"} create -f qcow2 \
          -b ${vm.diskoImages}/${disk.imageName}.qcow2 -F qcow2 "$NIX_DISK_IMAGE"
      fi
      exec ${vm.vm}/bin/run-${config.system.name}-vm "$@"
    '';

    # The `qemu-vm` settings for `system.build.vm`; a NixOS test imports them
    # itself.
    virtualisation.vmVariant.imports = [ ./pc-qemu.nix ];
  };
}
