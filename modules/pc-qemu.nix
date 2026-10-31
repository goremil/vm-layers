# The `qemu-vm` settings of a `pc` guest: boot the built disk through the
# firmware, with no direct kernel boot, no host store and no file systems of
# the module's own. OVMF supports Secure Boot by default in nixpkgs unstable.
{ config, lib, ... }:
{
  virtualisation = {
    directBoot.enable = false;
    mountHostNixStore = false;
    useDefaultFilesystems = false;
    fileSystems = lib.mkForce { };
    useEFIBoot = true;
    tpm.enable = true;
  };

  # The run script passes its consoles to the kernel only on a direct boot; a
  # boot through the firmware takes them from the installed boot entry.
  boot.kernelParams = map (console: "console=${console}") config.virtualisation.qemu.consoles;
}
