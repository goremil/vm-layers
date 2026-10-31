# USB devices lent to the Windows guest for a session only (ADR 0002), a
# NixOS module. The VM's QEMU runs as the user and USB device nodes are
# root:root 0664, so it cannot take a device by itself.
#
# `winvm usb attach <name>` (the home-manager module winvm.nix) runs
# `sudo winvm-usb-acl grant <name>`: an ACL for the user on that one
# /dev/bus/usb node, then QEMU takes the device (detaching the host driver).
# `detach` gives it back and `revoke` drops the ACL. Only devices on the
# allow-list: anything else (a YubiKey, the keyboard) stays out of reach
# of a process running as the user. The host overlay sets the user and the list.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.winvm.usb;
  inherit (cfg) allowed user;

  winvmUsbAcl = pkgs.writeShellApplication {
    name = "winvm-usb-acl";
    runtimeInputs = [
      pkgs.acl
      pkgs.coreutils
    ];
    text = ''
      declare -A allowed=(${
        builtins.concatStringsSep " " (
          builtins.attrValues (builtins.mapAttrs (n: id: "[${n}]=${id}") allowed)
        )
      })

      usage() { echo "usage: winvm-usb-acl grant|revoke <name> | list" >&2; exit 2; }

      [ "''${1:-}" = list ] && { for n in "''${!allowed[@]}"; do echo "$n ''${allowed[$n]}"; done; exit 0; }
      [ $# -eq 2 ] || usage
      action=$1; name=$2
      id=''${allowed[$name]:-}
      [ -n "$id" ] || { echo "winvm-usb-acl: '$name' is not on the allow-list" >&2; exit 1; }

      # Exactly one matching device, found through sysfs.
      found=()
      for d in /sys/bus/usb/devices/*; do
        [ -f "$d/idVendor" ] && [ -f "$d/idProduct" ] || continue
        if [ "$(<"$d/idVendor"):$(<"$d/idProduct")" = "$id" ]; then found+=("$d"); fi
      done
      [ ''${#found[@]} -eq 1 ] || { echo "winvm-usb-acl: $name ($id): ''${#found[@]} devices found, need exactly one" >&2; exit 1; }
      bus=$(<"''${found[0]}/busnum"); addr=$(<"''${found[0]}/devnum")
      node=$(printf '/dev/bus/usb/%03d/%03d' "$bus" "$addr")

      case "$action" in
        grant) setfacl -m u:${user}:rw "$node" ;;
        revoke) setfacl -x u:${user} "$node" ;;
        *) usage ;;
      esac
      # For QEMU's usb-host: hostbus, hostaddr.
      echo "$bus $addr"
    '';
  };
in
{
  options.programs.winvm.usb = {
    enable = lib.mkEnableOption "`winvm-usb-acl`, the root helper that lends allow-listed USB devices to the Windows guest";

    user = lib.mkOption {
      type = lib.types.str;
      description = "The user QEMU runs as; gets the ACL and may run the helper through sudo.";
    };

    allowed = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        stick = "0781:5581";
      };
      description = "Devices that may be lent: a name for `winvm usb attach` to its `vendor:product` id.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ winvmUsbAcl ];

    # The rule names the profile path, which is what `winvm` calls.
    security.sudo.extraRules = [
      {
        users = [ user ];
        commands = [
          {
            command = "/run/current-system/sw/bin/winvm-usb-acl";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
}
