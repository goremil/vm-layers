# The `winvm` guest type (ADR 0002), a home-manager module: a Windows 11 Pro
# guest under Quickemu, with a fixed hardware identity so activation survives
# rebuilds of this definition and reinstalls, and the `winvm` command:
# `install` (unattended, key and password from files read at run time),
# `finish`, `check`, `activate`, and the declared guest state (debloat,
# languages, preferences): general entries from winvm-debloat/, plus the host
# overlay's own.
#
# Quickemu takes the VM directory from `disk_img`, not from where the .conf
# lives (checked in quickemu 4.9.9), so the .conf can stay a read-only store
# file; the disk, OVMF_VARS copy, swtpm state, sockets and logs all go to
# $XDG_DATA_HOME/winvm/windows-11/ (data the tool manages).
#
# The host overlay sets the options (`programs.winvm`): the hardware identity,
# the guest's account and locale, the secret files, the profiles and the
# guest-state files. USB lending needs the NixOS module winvm-usb.nix too.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.winvm;

  # quickemu 4.9.9 walks its firmware candidates without a `break`, so the
  # last existing pair wins: QEMU's own edk2-x86_64-secure-code.fd with
  # edk2-x86_64-code.fd (a code image) copied in as the vars file -- Secure
  # Boot "on" with no keys enrolled. nixpkgs puts its OVMF with Microsoft's
  # keys (OVMF_VARS.ms.fd) first in that list, so first match wins here.
  # Found on a test start 2026-10-11; drop once upstream picks the first match.
  quickemu = pkgs.quickemu.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace quickemu \
        --replace-fail 'EFI_EXTRA_VARS="''${2}"' 'EFI_EXTRA_VARS="''${2}"; break'
    '';
  });

  # The install media. Quickemu attaches `iso` (index 0), `fixed_iso` (1) and
  # VMDIR/unattended.iso (2), and Windows setup sees them as D:, E:, F: (the
  # layout quickget's own answer file relies on). Once the disk is in use,
  # Quickemu attaches neither `iso` nor unattended.iso again.
  virtioIso = pkgs.runCommand "virtio-win.iso" { nativeBuildInputs = [ pkgs.xorriso ]; } ''
    xorriso -as mkisofs -quiet -J -joliet-long -R -V VIRTIO_WIN -o $out ${pkgs.virtio-win}
  '';

  # Answer file template: no secrets in the store. `winvm install` replaces
  # @PRODUCT_KEY@ and @PASSWORD@ (XML-escaped) when it writes unattended.iso
  # into the VM directory. No requirement bypasses: the guest has a
  # virtual TPM 2.0 (swtpm) and Secure Boot. The key selects the Pro
  # edition. The UI language must be the ISO's (`locale.ui`).
  autounattend = pkgs.writeText "autounattend.xml.in" ''
    <?xml version="1.0" encoding="utf-8"?>
    <unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <settings pass="windowsPE">
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
          <SetupUILanguage><UILanguage>${cfg.locale.ui}</UILanguage></SetupUILanguage>
          <InputLocale>${cfg.locale.input}</InputLocale>
          <SystemLocale>${cfg.locale.formats}</SystemLocale>
          <UILanguage>${cfg.locale.ui}</UILanguage>
          <UserLocale>${cfg.locale.formats}</UserLocale>
        </component>
        <component name="Microsoft-Windows-PnpCustomizationsWinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
          <DriverPaths>
            <PathAndCredentials wcm:action="add" wcm:keyValue="1"><Path>E:\viostor\w11\amd64</Path></PathAndCredentials>
            <PathAndCredentials wcm:action="add" wcm:keyValue="2"><Path>E:\vioscsi\w11\amd64</Path></PathAndCredentials>
            <PathAndCredentials wcm:action="add" wcm:keyValue="3"><Path>E:\NetKVM\w11\amd64</Path></PathAndCredentials>
          </DriverPaths>
        </component>
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
          <DiskConfiguration>
            <Disk wcm:action="add">
              <DiskID>0</DiskID>
              <WillWipeDisk>true</WillWipeDisk>
              <CreatePartitions>
                <CreatePartition wcm:action="add"><Order>1</Order><Type>EFI</Type><Size>260</Size></CreatePartition>
                <CreatePartition wcm:action="add"><Order>2</Order><Type>MSR</Type><Size>16</Size></CreatePartition>
                <CreatePartition wcm:action="add"><Order>3</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition>
              </CreatePartitions>
              <ModifyPartitions>
                <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Label>System</Label><Format>FAT32</Format></ModifyPartition>
                <ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>2</PartitionID></ModifyPartition>
                <ModifyPartition wcm:action="add"><Order>3</Order><PartitionID>3</PartitionID><Label>Windows</Label><Letter>C</Letter><Format>NTFS</Format></ModifyPartition>
              </ModifyPartitions>
            </Disk>
          </DiskConfiguration>
          <ImageInstall>
            <OSImage>
              <InstallTo><DiskID>0</DiskID><PartitionID>3</PartitionID></InstallTo>
              <InstallToAvailablePartition>false</InstallToAvailablePartition>
            </OSImage>
          </ImageInstall>
          <UserData>
            <AcceptEula>true</AcceptEula>
            <FullName>${cfg.user.fullName}</FullName>
            <ProductKey>
              <Key>@PRODUCT_KEY@</Key>
              <WillShowUI>OnError</WillShowUI>
            </ProductKey>
          </UserData>
        </component>
      </settings>
      <settings pass="specialize">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
          <ComputerName>${cfg.computerName}</ComputerName>
          <TimeZone>${cfg.locale.timeZone}</TimeZone>
        </component>
        <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
          <RunSynchronous>
            <RunSynchronousCommand wcm:action="add">
              <Order>1</Order>
              <Description>No automatic device encryption (BitLocker), set before OOBE starts it</Description>
              <Path>reg add HKLM\SYSTEM\CurrentControlSet\Control\BitLocker /v PreventDeviceEncryption /t REG_DWORD /d 1 /f</Path>
            </RunSynchronousCommand>
            <RunSynchronousCommand wcm:action="add">
              <Order>2</Order>
              <Description>winvm debloat before OOBE: registry (HKCU into the default user), services, provisioned apps</Description>
              <Path>cmd /c for %d in (D E F G H I) do @if exist %d:\winvm-setup.ps1 powershell -NoProfile -ExecutionPolicy Bypass -File %d:\winvm-setup.ps1 -Phase specialize</Path>
            </RunSynchronousCommand>
          </RunSynchronous>
        </component>
      </settings>
      <settings pass="oobeSystem">
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
          <InputLocale>${cfg.locale.input}</InputLocale>
          <SystemLocale>${cfg.locale.formats}</SystemLocale>
          <UILanguage>${cfg.locale.ui}</UILanguage>
          <UserLocale>${cfg.locale.formats}</UserLocale>
        </component>
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
          <OOBE>
            <HideEULAPage>true</HideEULAPage>
            <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
            <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
            <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
            <ProtectYourPC>3</ProtectYourPC>
          </OOBE>
          <UserAccounts>
            <LocalAccounts>
              <LocalAccount wcm:action="add">
                <Name>${cfg.user.name}</Name>
                <DisplayName>${cfg.user.name}</DisplayName>
                <Group>Administrators</Group>
                <Password><Value>@PASSWORD@</Value><PlainText>true</PlainText></Password>
              </LocalAccount>
            </LocalAccounts>
          </UserAccounts>
          <AutoLogon>
            <Username>${cfg.user.name}</Username>
            <Password><Value>@PASSWORD@</Value><PlainText>true</PlainText></Password>
            <Enabled>true</Enabled>
            <LogonCount>1</LogonCount>
          </AutoLogon>
          <FirstLogonCommands>
            <SynchronousCommand wcm:action="add">
              <Order>1</Order>
              <Description>winvm first-logon setup from the unattend media</Description>
              <CommandLine>cmd /c for %d in (D E F G H I) do @if exist %d:\winvm-setup.ps1 powershell -NoProfile -ExecutionPolicy Bypass -File %d:\winvm-setup.ps1</CommandLine>
            </SynchronousCommand>
          </FirstLogonCommands>
        </component>
      </settings>
    </unattend>
  '';

  # Run from the answer-file disk in two phases. specialize (before OOBE):
  # the debloat entries that need no user session. firstlogon: virtio
  # drivers, QEMU guest agent and SPICE agent (virtio-win-guest-tools),
  # OpenSSH Server with the VM's own key, then the declared state.
  # The debloat runs as a child process with a time limit: nothing in an
  # unattended phase may wait for a person (the specialize pass hung on a
  # service stuck in "stop pending" on 2026-10-17 until Ctrl+C). Past the
  # limit it is stopped and setup goes on; `winvm debloat` finishes the job.
  # Logs: C:\Windows\Temp\winvm-setup.log, winvm-debloat.log.
  setupScript = pkgs.writeText "winvm-setup.ps1" ''
    param([ValidateSet('specialize', 'firstlogon')] [string]$Phase = 'firstlogon')
    Start-Transcript -Path C:\Windows\Temp\winvm-setup.log -Append
    $src = Split-Path -Parent $MyInvocation.MyCommand.Path
    $debloat = Join-Path $src 'winvm-debloat.ps1'
    function Invoke-Debloat([string]$mode, [int]$minutes) {
      if (-not (Test-Path $debloat)) { return }
      $p = Start-Process powershell.exe -NoNewWindow -PassThru -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $debloat, '-Mode', $mode
      if (-not $p.WaitForExit($minutes * 60000)) {
        Stop-Process -Id $p.Id -Force
        "winvm-debloat -Mode $mode stopped after $minutes min; 'winvm debloat' finishes it"
      }
    }
    if ($Phase -eq 'specialize') {
      Invoke-Debloat specialize 15
      Stop-Transcript
      exit 0
    }
    $virtio = Get-PSDrive -PSProvider FileSystem | Where-Object { Test-Path (Join-Path $_.Root 'virtio-win-guest-tools.exe') } | Select-Object -First 1
    if ($virtio) { Start-Process -Wait -FilePath (Join-Path $virtio.Root 'virtio-win-guest-tools.exe') -ArgumentList '/install', '/quiet', '/norestart' }
    Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    Set-Service -Name sshd -StartupType Automatic
    Start-Service sshd
    Copy-Item (Join-Path $src 'administrators_authorized_keys') 'C:\ProgramData\ssh\administrators_authorized_keys' -Force
    icacls.exe 'C:\ProgramData\ssh\administrators_authorized_keys' /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F'
    New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -PropertyType String -Force
    powercfg.exe /hibernate off
    net.exe accounts /maxpwage:unlimited
    New-Item -ItemType Directory -Path C:\ProgramData\winvm -Force | Out-Null
    # The profile's pins, when it has captured ones.
    if (Test-Path (Join-Path $src 'layout')) { Copy-Item (Join-Path $src 'layout') C:\ProgramData\winvm\layout -Recurse -Force }
    Copy-Item (Join-Path $src 'taskmgr-settings.json') C:\ProgramData\winvm -Force -ErrorAction SilentlyContinue
    # Which VM profile this guest is; the debloat reads it (sign-in).
    Copy-Item (Join-Path $src 'profile.txt') C:\ProgramData\winvm -Force -ErrorAction SilentlyContinue
    Invoke-Debloat apply 60
    Stop-Transcript
  '';

  # The declared state of the guest; read-only `--check`, `apply`, `clean`.
  # One script, so the copy the logon task runs is the script itself ($self):
  # the engine, the option values, the general entries, the host's entries,
  # the modes. Windows PowerShell 5.1 reads a BOM-less file as ANSI, so the
  # build refuses anything but ASCII.
  psString = s: "'${lib.replaceStrings [ "'" ] [ "''" ] s}'";
  debloatValues = pkgs.writeText "winvm-debloat-values.ps1" ''
    # ---------------------------------------------------------------- values --
    # From the programs.winvm options.
    $winvmUser = ${psString cfg.user.name}
    $winvmComputerName = ${psString cfg.computerName}
    $winvmKeyboard = ${psString (lib.last (lib.splitString ":" cfg.locale.input))}
    $winvmAutoLogon = @(${
      lib.concatMapStringsSep ", " psString (
        lib.attrNames (lib.filterAttrs (_: p: p.autoLogon) cfg.profiles)
      )
    })
  '';
  debloatScript =
    pkgs.runCommand "winvm-debloat.ps1"
      {
        parts = [
          ./winvm-debloat/engine.ps1
          debloatValues
        ]
        ++ lib.optional cfg.debloat.defaults ./winvm-debloat/entries.ps1
        ++ cfg.debloat.extraEntries
        ++ [ ./winvm-debloat/modes.ps1 ];
      }
      ''
        for p in $parts; do
          cat "$p"
          echo
        done >"$out"
        if [ -n "$(LC_ALL=C tr -d '\0-\177' <"$out")" ]; then
          echo "winvm-debloat.ps1: not ASCII (Windows PowerShell 5.1 reads it as ANSI)" >&2
          exit 1
        fi
      '';
  inherit (cfg) taskmgrSettings;
  # A profile without a directory under layoutDir keeps Windows' own pins.
  layoutFor =
    profile:
    if cfg.layoutDir != null && builtins.pathExists (cfg.layoutDir + "/${profile}") then
      "${cfg.layoutDir + "/${profile}"}"
    else
      "";

  keyFile = cfg.productKeyFile;
  inherit (cfg) passwordFile;
  # The swtpm state (base64), the TPM half of the machine's identity; see ensure_tpm.
  tpmFile = cfg.tpmStateFile;

  # Profiles: one guest identity, one disk per profile, never two running at
  # once. The default (no --profile) is the general guest. Quickemu names its
  # files after the .conf, so each profile has its own VM directory, sockets,
  # ports and logs.
  vmBase = "windows-11";
  inherit (cfg) identity;
  profiles = lib.attrNames cfg.profiles;
  # " (NAME: note, ...)" after the default in winvm's usage.
  profileNotes =
    let
      noted = lib.filterAttrs (_: p: p.note != "") cfg.profiles;
    in
    lib.optionalString (noted != { })
      " (${lib.concatStringsSep ", " (lib.mapAttrsToList (n: p: "${n}: ${p.note}") noted)})";
  vmName = profile: if profile == "default" then vmBase else "${vmBase}-${profile}";
  vmDir = profile: "${config.xdg.dataHome}/winvm/${vmName profile}";

  # Type 0 is fixed too, or the BIOS strings would follow OVMF's version on
  # every nixpkgs bump.
  smbios = [
    "type=0,vendor=QEMU,version=${cfg.smbios.biosVersion},date=${cfg.smbios.biosDate}"
    "type=1,manufacturer=QEMU,product=${cfg.smbios.product},version=1,serial=${identity.serial},uuid=${identity.uuid}"
    "type=2,manufacturer=QEMU,product=${cfg.smbios.product},version=1,serial=${identity.serial}"
  ];

  # quickemu word-splits `extra_args` unquoted, so no value may hold a space.
  # Its `macaddr` only reaches a bridged NIC; on the default user-mode network
  # the MAC is set as a device default instead. `public_dir="none"`: no
  # ~/Public share (Samba, WebDAV, SPICE folder) into a guest that runs
  # untrusted binaries for reverse engineering. `dump-guest-core=off`: a QEMU
  # crash would otherwise write the guest's RAM (16G, with whatever the guest
  # holds -- during an install the product key and password) into a
  # systemd-coredump file; QEMU's own memory stays in the dump for debugging.
  # (Seen 2026-10-11: QEMU 11.1.1 crashed (SIGSEGV) at exit in spice-server's
  # InputsChannel::release_keys and left a 1.9G core.)
  # `-no-shutdown`: QEMU 11.1.1 crashes (SIGSEGV in spice-server's
  # InputsChannel::release_keys) when it exits with the SPICE window still
  # connected -- twice on 2026-10-11, the second time together with a hung
  # BTD 700 dongle and Discord dropping out. After the guest powers off,
  # QEMU now waits; `winvm watch` closes the window first, then quits QEMU.
  vmConf =
    profile:
    pkgs.writeTextDir "${vmName profile}.conf" ''
      guest_os="windows"
      disk_img="${vmDir profile}/disk.qcow2"
      disk_size="128G"
      cpu_cores="8"
      ram="16G"
      tpm="on"
      secureboot="on"
      display="spice"
      width="1920"
      height="1080"
      public_dir="none"
      iso="${vmDir profile}/${vmName profile}.iso"
      fixed_iso="${virtioIso}"
      extra_args="-no-shutdown -machine dump-guest-core=off -uuid ${identity.uuid} -global virtio-net-pci.mac=${identity.mac} ${
        toString (map (s: "-smbios ${s}") smbios)
      }"
    '';

  # select_profile's case arms in winvm.
  profileCases = lib.concatMapStrings (p: ''
    ${p}) name=${vmName p}; vm_dir="${vmDir p}"; conf="${vmConf p}/${vmName p}.conf"; layout="${layoutFor p}"; auto_logon=${
      lib.optionalString cfg.profiles.${p}.autoLogon "1"
    } ;;
  '') profiles;

  winvm = pkgs.writeShellApplication {
    name = "winvm";
    runtimeInputs = [
      quickemu
      pkgs.socat
      pkgs.openssh
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnused
      pkgs.xorriso
      pkgs.procps
      pkgs.gnugrep
      pkgs.spice-gtk
    ];
    text = ''
      # bash 5.2 would read `&` in a ''${x//a/b} replacement as the match.
      shopt -u patsub_replacement 2>/dev/null || true

      key_file="${keyFile}"
      password_file="${passwordFile}"
      tpm_file="${tpmFile}"

      # --profile NAME anywhere on the command line. Without it: the profile
      # whose VM is running (one at most), else the default.
      profile=
      args=()
      while [ $# -gt 0 ]; do
        case "$1" in
          --profile) profile=''${2:?--profile needs a name}; shift 2 ;;
          --profile=*) profile=''${1#--profile=}; shift ;;
          *) args+=("$1"); shift ;;
        esac
      done
      set -- "''${args[@]}"

      usage() {
        cat <<EOF
      usage: winvm [--profile NAME] COMMAND     profiles: ${toString profiles}; without --profile, the
                                                running one, else default${profileNotes}
             winvm start [--scratch]            start the VM (or reopen its SPICE window); --scratch discards every disk write at exit
                                                SPICE window: Shift+F11 full screen, Shift+F12 releases the grab and leaves it
             winvm stop [--wait]                ACPI shutdown (as the power button); --wait returns once QEMU has quit
             winvm install                      download the ISO, write the answer file, boot the unattended install
             winvm finish                       after the install: remove clear-text answer files (guest and host)
             winvm check                        print edition, activation, Secure Boot, TPM, identity, agents
             winvm debloat [--check]            apply the declared guest state (debloat, languages, preferences); --check only reports
             winvm clean                        empty the recycle bin, temp folders and caches, clean the component store, TRIM
             winvm activate                     install the product key from its file and activate (fallback)
             winvm usb list                     the devices that may be lent (allow-list on the host)
             winvm usb attach|detach NAME       lend an allow-listed USB device to the guest, or give it back
             winvm put FILE... --to DIR [--from DIR]
                                                copy files or directories into the guest folder DIR (with a drive
                                                letter; no default); --from: host base for relative FILEs
             winvm get PATH... --to DIR [--from DIR]
                                                copy from the guest into the host folder DIR (no default); a PATH
                                                without a drive letter needs --from, the guest folder it is under
             winvm ssh [args...]                ssh ${cfg.user.name}@ the guest through the forwarded port
             winvm conf                         print the path of the VM definition
      EOF
      }

      die() { echo "winvm: $*" >&2; exit 1; }

      mon() {
        [ -S "$monitor" ] || die "the VM is not running ($monitor missing)"
        printf '%s\n' "$1" | socat - "unix-connect:$monitor"
      }

      ssh_port() {
        sed -n 's/^ssh,//p' "$vm_dir/$name.ports" 2>/dev/null || true
      }

      guest() {
        port=$(ssh_port)
        [ -n "$port" ] || die "no forwarded ssh port; is the VM running?"
        ssh -p "$port" -i "$ssh_key" -o IdentitiesOnly=yes \
          -o UserKnownHostsFile="$vm_dir/ssh/known_hosts" -o StrictHostKeyChecking=accept-new \
          ${cfg.user.name}@localhost "$@"
      }

      # scp (SFTP) with the VM's key; a guest path C:\x\y is /C:/x/y there.
      guest_scp() {
        port=$(ssh_port)
        [ -n "$port" ] || die "no forwarded ssh port; is the VM running?"
        scp -r -P "$port" -i "$ssh_key" -o IdentitiesOnly=yes \
          -o UserKnownHostsFile="$vm_dir/ssh/known_hosts" -o StrictHostKeyChecking=accept-new "$@"
      }

      guest_path() {
        local p=''${1//\\//}
        case "$p" in
          [A-Za-z]:*) p="/$p" ;;
        esac
        printf '${cfg.user.name}@localhost:%s' "$p"
      }

      # A whole script file copied in and run with its arguments, then
      # removed. (Read from stdin as one script block it hung once in
      # [Console]::In.ReadToEnd(), 2026-10-11; guest_ps below runs stdin line by line.)
      # The output appears when the script has finished, not as it runs.
      guest_script() {
        local file=$1; shift
        local remote='C:\Windows\Temp\winvm-run.ps1'
        guest_scp "$file" "$(guest_path "$remote")" >/dev/null
        local rc=0
        # Output goes to a file first: a process the script starts (once,
        # 2026-10-11) may inherit the SSH session's output and keep the
        # connection open after PowerShell has exited.
        guest "powershell -NoProfile -ExecutionPolicy Bypass -File $remote $* *> $remote.out; \$c = \$LASTEXITCODE; Get-Content $remote.out; Remove-Item $remote, $remote.out; exit \$c" || rc=$?
        return "$rc"
      }

      # A PowerShell script on stdin, so secrets never reach a command line.
      # One statement per line: `-Command -` runs stdin line by line.
      guest_ps() {
        guest powershell -NoProfile -NonInteractive -Command -
      }

      ps_quote() {
        printf "'%s'" "''${1//\'/\'\'}"
      }

      xml_escape() {
        local v=$1
        v=''${v//&/&amp;}; v=''${v//</&lt;}; v=''${v//>/&gt;}; v=''${v//\"/&quot;}; v=''${v//\'/&apos;}
        printf '%s' "$v"
      }

      secrets() {
        [ -r "$key_file" ] && [ -r "$password_file" ] ||
          die "secret files unreadable (productKeyFile $key_file, passwordFile $password_file): are they in place?"
        product_key=$(tr -d '[:space:]' <"$key_file")
        password=$(<"$password_file")
      }

      # The SPICE window, opened by winvm rather than Quickemu: native Wayland
      # spicy, the guest fixed at 1920x1080 (resize-guest off) and scaled to
      # the window (its size is the desktop's to set, for example a KWin
      # window rule on the class `spicy`). Shift+F11
      # enters full screen, Shift+F12 (release the grab) leaves it. spicy
      # rewrites its own settings file, so the two keys are set before each
      # start rather than owned by home-manager.
      open_viewer() {
        if systemctl --user --quiet is-active winvm-viewer.service; then
          return 0
        fi
        local settings="''${XDG_CONFIG_HOME:-$HOME/.config}/spicy/settings"
        mkdir -p "$(dirname "$settings")"
        [ -e "$settings" ] || printf '[general]\n' >"$settings"
        for kv in resize-guest=false scaling=true; do
          if grep -q "^''${kv%%=*}=" "$settings"; then
            sed -i "s/^''${kv%%=*}=.*/$kv/" "$settings"
          else
            sed -i "/^\[general\]/a $kv" "$settings"
          fi
        done
        # QEMU creates the socket a moment after Quickemu returns; spicy exits
        # at once without it. A transient user unit, like winvm-watch, so the
        # window outlives whatever started winvm (a background job of a
        # finished script did not survive, 2026-10-11).
        local n=0
        while [ ! -S "$vm_dir/$name.sock" ] && [ "$n" -lt 30 ]; do
          sleep 1
          n=$((n + 1))
        done
        systemd-run --user --quiet --collect --unit=winvm-viewer \
          "$(command -v spicy)" --uri="spice+unix://$vm_dir/$name.sock" --title $name
      }

      running() {
        [ -r "$vm_dir/$name.pid" ] && kill -0 "$(<"$vm_dir/$name.pid")" 2>/dev/null
      }

      # Sets name, vm_dir, conf and the paths under vm_dir for one profile.
      select_profile() {
        case "$1" in
          ${profileCases}
          *) die "unknown profile '$1' (profiles: ${toString profiles})" ;;
        esac
        iso="$vm_dir/$name.iso"
        monitor="$vm_dir/$name-monitor.socket"
        ssh_key="$vm_dir/ssh/id_ed25519"
      }

      # The TPM state is part of the machine Windows recognizes, like the
      # identity in the definition. A profile without one takes another
      # profile's (with the SSH key pair; not known_hosts: a new guest has its
      # own host key), else the copy in tpmStateFile (after a reinstall of the
      # host). Never a fresh TPM: every install is a reinstall on the same
      # machine, the same digital licence. Not the UEFI variables: they are no
      # part of the identity, and another profile's boot entries came before
      # the DVD and outlasted Quickemu's five Enter presses for setup's
      # "Press any key" (2026-10-17); Quickemu makes fresh ones from its template.
      ensure_tpm() {
        [ ! -e "$vm_dir/tpm2-00.permall" ] || return 0
        mkdir -p "$vm_dir"
        local p src
        for p in ${toString profiles}; do
          [ "$p" != "$profile" ] || continue
          src=$(select_profile "$p" && echo "$vm_dir")
          [ -e "$src/tpm2-00.permall" ] || continue
          cp "$src/tpm2-00.permall" "$vm_dir/"
          if [ ! -e "$ssh_key" ] && [ -e "$src/ssh/id_ed25519" ]; then
            [ -d "$vm_dir/ssh" ] || mkdir -m 700 "$vm_dir/ssh"
            cp "$src/ssh/id_ed25519" "$src/ssh/id_ed25519.pub" "$vm_dir/ssh/"
          fi
          echo "winvm: TPM state taken from profile $p (the same machine for Windows)"
          return 0
        done
        [ -r "$tpm_file" ] || die "no TPM state in any profile and tpmStateFile unreadable ($tpm_file): is it in place?"
        (umask 027 && base64 -d <"$tpm_file" >"$vm_dir/tpm2-00.permall")
        echo "winvm: TPM state restored from tpmStateFile (the same machine for Windows)"
      }

      # The profile running other than this one, if any.
      other_running() {
        local p
        for p in ${toString profiles}; do
          [ "$p" != "$profile" ] || continue
          if (select_profile "$p" && running); then echo "$p"; return 0; fi
        done
        return 1
      }

      if [ -z "$profile" ]; then
        profile=default
        if p=$(other_running); then profile=$p; fi
      fi
      select_profile "$profile"

      case "''${1:-}" in
        start)
          if p=$(other_running); then die "profile $p is running; stop it first (one profile at a time: one identity)"; fi
          running || ensure_tpm
          if [ "''${2:-}" = --scratch ]; then
            # A running VM would only get its window reopened, with its writes kept.
            ! running || die "the VM is already running; stop it before a scratch session"
            # --status-quo is QEMU's -snapshot: disk and UEFI-variable writes go to
            # an unlinked temporary file in TMPDIR, gone when QEMU exits (a crash
            # included). The swtpm state is still kept. TMPDIR on the VM's no-CoW
            # directory, not /tmp (tmpfs: RAM).
            TMPDIR="$vm_dir" quickemu --vm "$conf" --status-quo --viewer none
          elif ! running; then
            quickemu --vm "$conf" --viewer none
          fi
          open_viewer
          # One watcher per running VM; a second `start` only reopens the window.
          if ! systemctl --user --quiet is-active winvm-watch.service; then
            systemd-run --user --quiet --collect --unit=winvm-watch "$(readlink -f "$0")" --profile "$profile" watch
          fi
          ;;
        watch)
          # QEMU runs with -no-shutdown: once the guest is off, close the SPICE
          # window, then quit QEMU with no client connected.
          pid=$(<"$vm_dir/$name.pid")
          while kill -0 "$pid" 2>/dev/null; do
            # With -no-shutdown a powered-off guest reads "VM status: paused (shutdown)".
            if mon "info status" 2>/dev/null | grep -q 'VM status: .*shutdown'; then
              pkill -u "$(id -u)" -f "spice\\+unix://$vm_dir/$name\\.sock" || true
              sleep 2
              mon quit >/dev/null 2>&1 || true
              break
            fi
            sleep 2
          done
          ;;
        stop)
          mon system_powerdown >/dev/null
          if [ "''${2:-}" = --wait ]; then
            # winvm-watch quits QEMU once the guest is off. A scratch guest
            # ignored the ACPI request once shortly after boot (2026-10-11), so
            # after 60 s ask Windows over SSH.
            n=0
            while running; do
              n=$((n + 1))
              # In parentheses: guest() exits through die() when no port is forwarded.
              [ "$n" -ne 30 ] || (guest 'shutdown /s /t 0') >/dev/null 2>&1 || true
              sleep 2
            done
          fi
          ;;
        install)
          if p=$(other_running); then die "profile $p is running; stop it first (one profile at a time: one identity)"; fi
          secrets
          umask 077
          [ ! -e "$vm_dir/disk.qcow2" ] ||
            die "$vm_dir/disk.qcow2 exists; for a reinstall delete only that file (the TPM and UEFI state stay)"
          mkdir -p "$vm_dir"
          ensure_tpm
          if [ ! -e "$iso" ]; then
            tmp=$(mktemp -d "$vm_dir/download.XXXXXX")
            (cd "$tmp" && quickget --download windows 11 ${lib.escapeShellArg cfg.locale.isoLanguage}) || true
            found=$(find "$tmp" -name '*.iso' -size +1G | head -n 1)
            [ -n "$found" ] || die ${lib.escapeShellArg "the ISO download failed; download Windows 11 (${cfg.locale.isoLanguage}) by hand and save it as "}"$iso"
            mv "$found" "$iso"
            rm -rf "$tmp"
          fi
          if [ ! -e "$ssh_key" ]; then
            mkdir -m 700 "$vm_dir/ssh"
            ssh-keygen -q -t ed25519 -N "" -C "winvm@$name" -f "$ssh_key"
          fi
          work=$(mktemp -d "$vm_dir/unattended.XXXXXX")
          template=$(<"${autounattend}")
          template=''${template//@PRODUCT_KEY@/$(xml_escape "$product_key")}
          template=''${template//@PASSWORD@/$(xml_escape "$password")}
          printf '%s\n' "$template" >"$work/autounattend.xml"
          cp "${setupScript}" "$work/winvm-setup.ps1"
          cp "${debloatScript}" "$work/winvm-debloat.ps1"
          [ -z "$layout" ] || cp -r "$layout" "$work/layout"
          cp "${taskmgrSettings}" "$work/taskmgr-settings.json"
          printf '%s\n' "$profile" >"$work/profile.txt"
          cp "$ssh_key.pub" "$work/administrators_authorized_keys"
          xorriso -as mkisofs -quiet -J -o "$vm_dir/unattended.iso" "$work"
          rm -rf "$work"
          echo "winvm: unattended.iso holds the key and password in clear text; run 'winvm finish' after the install"
          quickemu --vm "$conf" --viewer none
          open_viewer
          # The watcher as for start: without it QEMU (-no-shutdown) stayed
          # paused after the installed guest powered off, and stop --wait
          # waited for ever (2026-10-17).
          if ! systemctl --user --quiet is-active winvm-watch.service; then
            systemd-run --user --quiet --collect --unit=winvm-watch "$(readlink -f "$0")" --profile "$profile" watch
          fi
          ;;
        finish)
          secrets
          {
            echo "\$k = $(ps_quote "$product_key")"
            echo "\$p = $(ps_quote "$password")"
            cat <<'EOF'
      $hits = Get-ChildItem -Path C:\Windows\Panther, C:\Windows\System32\Sysprep -Recurse -File -Include *.xml -ErrorAction SilentlyContinue | Where-Object { (Select-String -Path $_.FullName -SimpleMatch -Pattern $k, $p -Quiet) }
      foreach ($f in $hits) { Remove-Item -Force $f.FullName; "removed $($f.FullName)" }
      if (-not $hits) { 'no clear-text answer file found in the guest' }
      EOF
          } | guest_ps
          rm -f "$vm_dir/unattended.iso"
          echo "winvm: removed $vm_dir/unattended.iso"
          ;;
        check)
          guest_ps <<'EOF'
      $os = Get-CimInstance Win32_OperatingSystem; "edition:     $($os.Caption) $($os.Version)"
      $lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'"; "licence:     $($lic.Name) status=$($lic.LicenseStatus) (1 = licensed)"
      "secure boot: $(Confirm-SecureBootUEFI)"
      $tpm = Get-Tpm; "tpm:         present=$($tpm.TpmPresent) ready=$($tpm.TpmReady)"
      $p = Get-CimInstance Win32_ComputerSystemProduct; "uuid:        $($p.UUID)"
      "serial:      $((Get-CimInstance Win32_BIOS).SerialNumber)"
      "mac:         $((Get-NetAdapter | Select-Object -First 1).MacAddress)"
      Get-Service QEMU-GA, spice-agent, sshd, TermService -ErrorAction SilentlyContinue | ForEach-Object { "service:     $($_.Name) $($_.Status)" }
      EOF
          ;;
        debloat)
          # Task Manager's settings and the profile's pins, restored by the
          # script from C:\ProgramData\winvm.
          guest 'New-Item -ItemType Directory -Path C:\ProgramData\winvm -Force | Out-Null' >/dev/null
          guest_scp "${taskmgrSettings}" "$(guest_path 'C:\ProgramData\winvm\taskmgr-settings.json')" >/dev/null
          # Which VM profile this guest is; the debloat reads it (sign-in).
          guest "Set-Content -Path C:\ProgramData\winvm\profile.txt -Value $profile" >/dev/null
          if [ -n "$auto_logon" ]; then
            # Auto logon in a profile that has it: the password from its file
            # goes in as the LSA secret DefaultPassword through stdin, never a
            # file or a command line; the debloat entry then turns auto logon on.
            secrets
            {
              echo "\$p = $(ps_quote "$password")"
              cat <<'EOF'
      $c = 'using System; using System.Runtime.InteropServices; public static class WinvmLsaStore { [StructLayout(LayoutKind.Sequential)] public struct US { public ushort Length, MaximumLength; public IntPtr Buffer; } [StructLayout(LayoutKind.Sequential)] public struct OA { public int Length; public IntPtr RootDirectory, ObjectName; public uint Attributes; public IntPtr SecurityDescriptor, SecurityQualityOfService; } [DllImport("advapi32.dll")] static extern uint LsaOpenPolicy(IntPtr s, ref OA oa, uint a, out IntPtr h); [DllImport("advapi32.dll")] static extern uint LsaStorePrivateData(IntPtr h, ref US k, ref US d); [DllImport("advapi32.dll")] static extern uint LsaClose(IntPtr h); static US S(string s) { var u = new US(); u.Buffer = Marshal.StringToHGlobalUni(s); u.Length = (ushort)(s.Length * 2); u.MaximumLength = (ushort)(s.Length * 2 + 2); return u; } public static void Store(string n, string v) { var oa = new OA(); oa.Length = Marshal.SizeOf(oa); IntPtr h; uint r = LsaOpenPolicy(IntPtr.Zero, ref oa, 0x000F0FFF, out h); if (r != 0) throw new Exception("LsaOpenPolicy 0x" + r.ToString("x")); try { var k = S(n); var d = S(v); r = LsaStorePrivateData(h, ref k, ref d); if (r != 0) throw new Exception("LsaStorePrivateData 0x" + r.ToString("x")); } finally { LsaClose(h); } } }'
      Add-Type -TypeDefinition $c
      [WinvmLsaStore]::Store('DefaultPassword', $p)
      'auto logon password stored'
      EOF
            } | guest_ps
          fi
          if [ -n "$layout" ]; then
            stage=$(mktemp -d)
            cp -r "$layout" "$stage/layout"
            chmod -R u+w "$stage"
            guest 'New-Item -ItemType Directory -Path C:\ProgramData\winvm -Force | Out-Null' >/dev/null
            guest_scp "$stage/layout" "$(guest_path 'C:\ProgramData\winvm')/" >/dev/null
            rm -rf "$stage"
          fi
          if [ "''${2:-}" = --check ]; then
            guest_script "${debloatScript}" -Mode check
          else
            guest_script "${debloatScript}" -Mode apply
          fi
          ;;
        clean)
          before=$(du -k "$vm_dir/disk.qcow2" | cut -f1)
          guest_script "${debloatScript}" -Mode clean
          after=$(du -k "$vm_dir/disk.qcow2" | cut -f1)
          echo "winvm: disk.qcow2 on the host $((before / 1024)) MiB -> $((after / 1024)) MiB"
          ;;
        activate)
          secrets
          {
            echo "\$k = $(ps_quote "$product_key")"
            # shellcheck disable=SC2016 # $k is PowerShell's, expanded in the guest
            echo 'cscript //nologo C:\Windows\System32\slmgr.vbs /ipk $k'
            echo 'cscript //nologo C:\Windows\System32\slmgr.vbs /ato'
          } | guest_ps
          ;;
        usb)
          # Allow-listed devices only, lent for a session: the root helper
          # (the NixOS module winvm-usb.nix) grants the user an ACL
          # on that one device node, QEMU takes the device; detach gives it
          # back to the host driver and drops the ACL.
          acl=/run/current-system/sw/bin/winvm-usb-acl
          action="''${2:-}"; name="''${3:-}"
          case "$action" in
            list) exec "$acl" list ;;
            attach)
              [ -n "$name" ] || { usage >&2; exit 2; }
              read -r bus addr < <(sudo -n "$acl" grant "$name") || die "no access to $name (see winvm usb list)"
              # quickemu's xhci controller for passthrough has id `spicepass`.
              mon "device_add usb-host,bus=spicepass.0,hostbus=$bus,hostaddr=$addr,id=usb-$name" >/dev/null
              sleep 1
              if mon "info usb" | grep -q "ID: usb-$name"; then
                echo "winvm: $name lent to the guest"
              else
                sudo -n "$acl" revoke "$name" >/dev/null || true
                die "QEMU did not take $name; access revoked"
              fi
              ;;
            detach)
              [ -n "$name" ] || { usage >&2; exit 2; }
              mon "device_del usb-$name" >/dev/null
              sleep 2 # QEMU releases the device and the host driver binds again
              sudo -n "$acl" revoke "$name" >/dev/null
              echo "winvm: $name given back to the host"
              ;;
            *) usage >&2; exit 2 ;;
          esac
          ;;
        put | get)
          # No default folders on either side (decided 2026-10-17): every
          # call names its destination with --to, so a consumer never copies
          # a folder it did not choose. Guest paths need a drive letter, or
          # are relative to an explicit --from; host paths are relative to the
          # current directory, or to --from for put.
          is_guest_abs() { case "$1" in [A-Za-z]:*) return 0 ;; *) return 1 ;; esac; }
          in_host() { # path base
            case "$1" in
              /*) printf '%s' "$1" ;;
              *) if [ -n "$2" ]; then printf '%s/%s' "$2" "$1"; else printf '%s' "$1"; fi ;;
            esac
          }
          mode=$1; shift
          from=""; to=""
          paths=()
          while [ $# -gt 0 ]; do
            case "$1" in
              --from) from=''${2:?--from needs a directory}; shift 2 ;;
              --to) to=''${2:?--to needs a directory}; shift 2 ;;
              *) paths+=("$1"); shift ;;
            esac
          done
          [ ''${#paths[@]} -gt 0 ] || { usage >&2; exit 2; }
          [ -n "$to" ] || die "$mode needs --to DIR (no default folder)"
          if [ "$mode" = put ]; then
            is_guest_abs "$to" || die "put --to needs a guest path with a drive letter: $to"
            local_paths=()
            for p in "''${paths[@]}"; do local_paths+=("$(in_host "$p" "$from")"); done
            guest_scp "''${local_paths[@]}" "$(guest_path "$to")/"
          else
            [ -z "$from" ] || is_guest_abs "$from" || die "get --from needs a guest path with a drive letter: $from"
            remote=()
            for p in "''${paths[@]}"; do
              if is_guest_abs "$p"; then
                remote+=("$(guest_path "$p")")
              elif [ -n "$from" ]; then
                remote+=("$(guest_path "$from\\$p")")
              else
                die "get: $p has no drive letter and no --from names its folder"
              fi
            done
            mkdir -p "$to"
            guest_scp "''${remote[@]}" "$to/"
          fi
          ;;
        ssh)
          shift
          guest "$@"
          ;;
        conf)
          echo "$conf"
          ;;
        *)
          usage >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  options.programs.winvm = {
    enable = lib.mkEnableOption "the Windows 11 guest under Quickemu and its `winvm` command";

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "The `winvm` command, for launcher entries.";
    };

    identity = {
      uuid = lib.mkOption {
        type = lib.types.str;
        description = "SMBIOS system UUID. Windows derives the device identity, and so its digital licence, from the identity: never change it after the first install.";
      };
      serial = lib.mkOption {
        type = lib.types.str;
        description = "SMBIOS serial number (types 1 and 2); part of the identity.";
      };
      mac = lib.mkOption {
        type = lib.types.str;
        description = "MAC address of the virtio NIC; part of the identity.";
      };
    };

    smbios = {
      biosVersion = lib.mkOption {
        type = lib.types.str;
        description = "SMBIOS type 0 BIOS version string; no spaces (Quickemu word-splits `extra_args`).";
      };
      biosDate = lib.mkOption {
        type = lib.types.str;
        description = "SMBIOS type 0 BIOS date, MM/DD/YYYY.";
      };
      product = lib.mkOption {
        type = lib.types.str;
        description = "SMBIOS product name (types 1 and 2), Windows' model name; no spaces.";
      };
    };

    user = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "The guest's local administrator account, also the SSH login.";
      };
      fullName = lib.mkOption {
        type = lib.types.str;
        default = cfg.user.name;
        defaultText = lib.literalExpression "config.programs.winvm.user.name";
        description = "The registered owner in the answer file.";
      };
    };

    computerName = lib.mkOption {
      type = lib.types.str;
      description = "The guest's computer name.";
    };

    locale = {
      ui = lib.mkOption {
        type = lib.types.str;
        description = "Windows display language; must be the install ISO's language.";
      };
      isoLanguage = lib.mkOption {
        type = lib.types.str;
        # Only the pairs checked on an install; quickget names its ISOs by
        # Microsoft's download names, not by language tags.
        default =
          {
            "en-US" = "English (United States)";
            "en-GB" = "English International";
          }
          .${cfg.locale.ui}
            or (throw "programs.winvm.locale.isoLanguage: no known ISO for locale.ui ${cfg.locale.ui}; set it to one of quickget's Windows languages");
        defaultText = lib.literalMD "`English (United States)` for `en-US`, `English International` for `en-GB`; any other `locale.ui` needs it set";
        description = "The ISO `winvm install` downloads, as quickget names its Windows languages (`quickget windows 11` lists them); its UI language must be `locale.ui`.";
      };
      formats = lib.mkOption {
        type = lib.types.str;
        default = cfg.locale.ui;
        defaultText = lib.literalExpression "config.programs.winvm.locale.ui";
        description = "System and user locale (formats).";
      };
      input = lib.mkOption {
        type = lib.types.str;
        description = "Input locale, `<language id>:<keyboard layout id>`.";
      };
      timeZone = lib.mkOption {
        type = lib.types.str;
        description = "Windows time zone name.";
      };
    };

    productKeyFile = lib.mkOption {
      type = lib.types.str;
      description = "Path to a file with the product key, read at run time (never copied into the store).";
    };
    passwordFile = lib.mkOption {
      type = lib.types.str;
      description = "Path to a file with the guest account's password, read at run time.";
    };
    tpmStateFile = lib.mkOption {
      type = lib.types.str;
      description = "Path to the swtpm state (`tpm2-00.permall`, base64), restored when no profile has one: the TPM half of the identity.";
    };

    profiles = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            autoLogon = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "`winvm debloat` stores the password as the LSA secret DefaultPassword, for a guest that signs in by itself.";
            };
            note = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "A short note on the profile in `winvm`'s usage.";
            };
          };
        }
      );
      default.default = { };
      description = "VM profiles: one identity, one disk each, never two running at once. `default` is the guest without `--profile`.";
    };

    layoutDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Directory with one subdirectory per profile holding its captured Start and taskbar pins.";
    };
    taskmgrSettings = lib.mkOption {
      type = lib.types.path;
      description = "Task Manager settings restored in every profile.";
    };
    debloat = {
      defaults = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "The general entries of the declared guest state (`winvm-debloat/entries.ps1`): Store apps, telemetry, AI, UI noise, idle services, sign-in and the like.";
      };
      extraEntries = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [ ];
        description = "The host's own entries, PowerShell (ASCII only) added after the general ones, with the same helpers (`Reg`, `Custom`, ...) and variables (`$vmProfile`, `$uiTag`, ...).";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    programs.winvm.package = winvm;

    home = {
      packages = [
        quickemu
        winvm
      ];

      # No copy-on-write for the images and state (btrfs CoW fragments them);
      # +C only takes effect on files created after it is set, so it is set on
      # the empty directory. quickemu also creates the qcow2 with nocow=on.
      activation.windowsVmDir = config.lib.dag.entryAfter [ "writeBoundary" ] (
        lib.concatMapStrings (p: ''
          if [ ! -d "${vmDir p}" ]; then
            run mkdir -p "${vmDir p}"
            run ${pkgs.e2fsprogs}/bin/chattr +C "${vmDir p}" || true
          fi
        '') profiles
      );
    };
  };
}
