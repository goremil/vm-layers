# A `pc` guest starts with Secure Boot off and asks for its passphrase,
# enrols the keys it generated on the next boot and binds its LUKS volume to
# the TPM2, and from the third boot on unlocks it with no passphrase.
{
  name = "pc";
  # Three boots take about a minute; a wait that never ends fails here.
  globalTimeout = 10 * 60;

  nodes.machine = {
    imports = [
      ../modules/pc-qemu.nix
      ../modules/testbed.nix
    ];
  };

  testScript =
    { nodes, ... }:
    let
      inherit (nodes) machine;
    in
    ''
      import os
      import subprocess
      import tempfile

      # A copy-on-write overlay over the built disk image, for the run script.
      disk = tempfile.NamedTemporaryFile()
      subprocess.run([
        "${machine.virtualisation.qemu.package}/bin/qemu-img", "create",
        "-f", "qcow2",
        "-b", "${machine.system.build.diskoImages}/main.qcow2",
        "-F", "qcow2",
        disk.name,
      ], check=True)
      os.environ["NIX_DISK_IMAGE"] = disk.name

      def unlock_with_passphrase():
        machine.wait_for_console_text(r"Please enter passphrase for disk .*\(cryptroot\)")
        machine.send_console("testbed\n")

      machine.start(allow_reboot=True)
      unlock_with_passphrase()

      with subtest("the root is a btrfs subvolume on LUKS2"):
        root = machine.succeed("findmnt -no SOURCE,FSTYPE /")
        t.assertIn("/dev/mapper/cryptroot[/@root] btrfs", root)
        machine.succeed("btrfs subvolume show /persist")

      with subtest("Secure Boot is off on the first boot"):
        t.assertIn("Secure Boot: disabled", machine.succeed("bootctl status"))

      with subtest("the guest generates its keys and prepares their enrolment"):
        machine.wait_for_unit("generate-sb-keys.service")
        machine.wait_for_unit("prepare-sb-auto-enroll.service")
        machine.succeed("test -f /boot/loader/keys/auto/db.auth")
        t.assertIn("✓", machine.succeed("sbctl verify"))

      machine.reboot()
      unlock_with_passphrase()

      with subtest("Secure Boot is on after the enrolment"):
        t.assertIn("Secure Boot: enabled (user)", machine.succeed("bootctl status"))

      with subtest("the guest binds its LUKS volume to the TPM2"):
        machine.wait_for_unit("pc-tpm2-enroll.service")
        slots = machine.succeed("systemd-cryptenroll /dev/disk/by-partlabel/disk-main-root")
        t.assertIn("tpm2", slots)
        t.assertIn("password", slots)

      machine.reboot()

      with subtest("the TPM2 unlocks the volume, no passphrase"):
        # Nothing answers a passphrase prompt now, so a prompt ends in the timeout.
        machine.wait_for_unit("multi-user.target", timeout=120)
        t.assertIn("/dev/mapper/cryptroot", machine.succeed("findmnt -no SOURCE /"))
        t.assertIn("Secure Boot: enabled (user)", machine.succeed("bootctl status"))
    '';
}
