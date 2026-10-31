# winvm-debloat.ps1 -- the declared state of the Windows 11 guest.
# Built by modules/winvm.nix from modules/winvm-debloat/: this engine, the
# values of the options, the general entries (entries.ps1, unless
# debloat.defaults is off), the host's own (debloat.extraEntries), and the
# modes (modes.ps1). Run by winvm:
#   winvm debloat --check   -Mode check  read-only; every entry 'ok' or 'differs'
#   winvm debloat           -Mode apply  sets every entry that differs, then checks again
#   winvm clean             -Mode clean  one-shot cleanup (not state), then TRIM
#   specialize pass         -Mode specialize  from the answer file, before OOBE: the entries
#                                        that need no user session (HKCU into the default user)
#   first logon             -Mode apply  from the answer-file disk (winvm-setup.ps1)
#   at every logon          -Mode auto   scheduled task: apply again once the OS build changed
#                                        (an update can bring apps and settings back)
# Every change is reversible: values, policies, services, tasks, Store apps
# (from the Store), capabilities (through Windows Update). Windows Update,
# Defender, the Store, WebView2, .NET and Edge are never touched.
# Windows PowerShell 5.1 reads a BOM-less file as ANSI: keep this file ASCII.
param(
  [ValidateSet('check', 'apply', 'clean', 'auto', 'specialize')]
  [string]$Mode = 'check'
)

# This script's own text, for the copy the logon task runs (works from a file
# and from the script block winvm builds from stdin).
$self = $MyInvocation.MyCommand.ScriptBlock.ToString()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$log = 'C:\Windows\Temp\winvm-debloat.log'

# Written to the host, not the pipeline: Test-All returns only its count.
function Out-Line([string]$s) {
  Write-Host $s
  Add-Content -Path $log -Value ('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $s)
}

# ---------------------------------------------------------------- entries --
# Each entry is data: a kind and its arguments; Test-Entry and Set-Entry act on
# it. (No GetNewClosure(): its dynamic module hides this script's functions
# and $script: variables.) Kind 'custom' carries its own script blocks.
$entries = New-Object System.Collections.Generic.List[object]

function Add-Entry([string]$kind, [string]$name, [hashtable]$a) {
  $entries.Add([pscustomobject]@{ Kind = $kind; Name = $name; A = $a })
}

function Get-RegValue([string]$path, [string]$name) {
  $item = Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
  if ($null -eq $item) { return $null }
  return $item.$name
}

# A registry value; DWord unless a type is given.
function Reg([string]$path, [string]$name, $value, [string]$type = 'DWord') {
  Add-Entry 'reg' "reg $path\$name = $value" @{ Path = $path; Name = $name; Value = $value; Type = $type }
}
function RegAbsent([string]$path, [string]$name) {
  Add-Entry 'regabsent' "reg $path\$name absent" @{ Path = $path; Name = $name }
}
function Service([string]$name) { Add-Entry 'service' "service $name disabled" @{ Name = $name } }
# A per-user service: its template's Start value decides for every session
# instance (<name>_<suffix>); Set-Service does not reach templates.
function UserService([string]$name) { Add-Entry 'userservice' "user service $name disabled" @{ Name = $name } }
function Task([string]$path, [string]$name) { Add-Entry 'task' "task $path$name disabled" @{ Path = $path; Name = $name } }
# Removed for every user and as the provisioned copy, so no new profile gets it.
function Appx([string]$name) { Add-Entry 'appx' "appx $name removed" @{ Name = $name } }
function AppxPresent([string]$name, [string]$storeId) {
  Add-Entry 'appxpresent' "appx $name installed" @{ Name = $name; StoreId = $storeId }
}
# By name prefix: the version suffix differs between builds.
function Capability([string]$prefix) { Add-Entry 'capability' "capability $prefix* removed" @{ Prefix = $prefix } }
function Feature([string]$name) { Add-Entry 'feature' "feature $name disabled" @{ Name = $name } }
function Custom([string]$name, [scriptblock]$test, [scriptblock]$set) {
  Add-Entry 'custom' $name @{ Test = $test; Set = $set }
}

# The real account name: over SSH $env:USERDOMAIN reads WORKGROUP (2026-10-11).
$me = [Security.Principal.WindowsIdentity]::GetCurrent().Name

# Runs a command in the user's desktop session through a one-shot task:
# Store app registration is refused over SSH (a network logon, 0x80070005).
# Without a desktop session it throws, and the logon task does it later.
function Invoke-InUserSession([string]$command) {
  if (-not $env:SSH_CONNECTION) {
    & ([scriptblock]::Create($command)); return
  }
  if (-not (Get-Process -Name explorer -IncludeUserName -ErrorAction SilentlyContinue | Where-Object UserName -eq $me)) {
    throw "no desktop session of $me; the logon task does it at the next logon"
  }
  $out = 'C:\Windows\Temp\winvm-usersession.log'
  $full = "`$ErrorActionPreference = 'Stop'; try { $command; 'ok' | Out-File $out } catch { `$_.Exception.Message | Out-File $out; exit 1 }"
  $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($full))
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -EncodedCommand $enc"
  $principal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Highest
  Register-ScheduledTask -TaskPath '\winvm\' -TaskName 'user-session' -Action $action -Principal $principal -Force | Out-Null
  try {
    Remove-Item $out -ErrorAction SilentlyContinue
    Start-ScheduledTask -TaskPath '\winvm\' -TaskName 'user-session'
    $n = 0
    while (-not (Test-Path $out) -and $n -lt 300) { Start-Sleep -Seconds 1; $n++ }
    $result = (Get-Content -Raw $out -ErrorAction SilentlyContinue)
    if ("$result".Trim() -ne 'ok') { throw "in the desktop session: $result" }
  } finally {
    Unregister-ScheduledTask -TaskPath '\winvm\' -TaskName 'user-session' -Confirm:$false
  }
}

# Slow lookups, read once per pass.
$script:appx = @(); $script:provisioned = @(); $script:caps = @(); $script:features = @()
function Read-State {
  $script:appx = @(Get-AppxPackage -AllUsers | Select-Object -ExpandProperty Name)
  $script:provisioned = @(Get-AppxProvisionedPackage -Online | Select-Object -ExpandProperty DisplayName)
  $script:caps = @(Get-WindowsCapability -Online | Where-Object State -eq 'Installed' | Select-Object -ExpandProperty Name)
  $script:features = @(Get-WindowsOptionalFeature -Online | Where-Object State -eq 'Enabled' | Select-Object -ExpandProperty FeatureName)
}

function Test-Entry($e) {
  $a = $e.A
  switch ($e.Kind) {
    'reg' {
      $cur = Get-RegValue $a.Path $a.Name
      if ($null -eq $cur) { return $false }
      if ($a.Type -eq 'Binary') { return (@($cur) -join ',') -eq (@($a.Value) -join ',') }
      return "$cur" -eq "$($a.Value)"
    }
    'regabsent' { return $null -eq (Get-RegValue $a.Path $a.Name) }
    'service' {
      $svc = Get-Service -Name $a.Name -ErrorAction SilentlyContinue
      # Some refuse to stop while Windows runs; Disabled takes effect at the next boot.
      return ($null -eq $svc) -or ($svc.StartType -eq 'Disabled')
    }
    'userservice' {
      $start = Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Services\$($a.Name)" 'Start'
      return ($null -eq $start) -or ($start -eq 4)
    }
    'task' {
      $t = Get-ScheduledTask -TaskPath $a.Path -TaskName $a.Name -ErrorAction SilentlyContinue
      return ($null -eq $t) -or ($t.State -eq 'Disabled')
    }
    'appx' { return -not ($script:appx -contains $a.Name) -and -not ($script:provisioned -contains $a.Name) }
    'appxpresent' { return $null -ne (Get-AppxPackage -Name $a.Name) }
    'capability' { return -not ($script:caps | Where-Object { $_.StartsWith($a.Prefix) }) }
    'feature' { return -not ($script:features -contains $a.Name) }
    'custom' { return [bool](& $a.Test) }
  }
}

function Set-Entry($e) {
  $a = $e.A
  switch ($e.Kind) {
    'reg' {
      if (-not (Test-Path $a.Path)) { New-Item -Path $a.Path -Force | Out-Null }
      New-ItemProperty -Path $a.Path -Name $a.Name -Value $a.Value -PropertyType $a.Type -Force | Out-Null
    }
    'regabsent' { Remove-ItemProperty -Path $a.Path -Name $a.Name -Force }
    'service' {
      # Some services refuse Set-Service; their Start value is the same setting.
      try { Set-Service -Name $a.Name -StartupType Disabled }
      catch { Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($a.Name)" -Name Start -Value 4 }
      # -NoWait: Disabled is the setting, the stop only a courtesy. Without it
      # the first logon hung on iphlpsvc stuck in "stop pending" (2026-10-17).
      Stop-Service -Name $a.Name -Force -NoWait -ErrorAction SilentlyContinue
    }
    'userservice' {
      Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($a.Name)" -Name Start -Value 4
      Get-Service -Name "$($a.Name)_*" -ErrorAction SilentlyContinue | Stop-Service -Force -NoWait -ErrorAction SilentlyContinue
    }
    'task' { Disable-ScheduledTask -TaskPath $a.Path -TaskName $a.Name | Out-Null }
    'appx' {
      Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq $a.Name |
        Remove-AppxProvisionedPackage -Online -AllUsers | Out-Null
      Get-AppxPackage -AllUsers -Name $a.Name | Remove-AppxPackage -AllUsers
    }
    'appxpresent' {
      # Registered again from the copy Windows keeps (by family name; the
      # bundle has no AppxManifest.xml), else installed from the Store.
      $staged = Get-AppxPackage -AllUsers -Name $a.Name -PackageTypeFilter Main | Select-Object -First 1
      if ($staged) {
        Invoke-InUserSession "Add-AppxPackage -RegisterByFamilyName -MainPackage $($staged.PackageFamilyName)"
      } else {
        Invoke-InUserSession "winget.exe install --id $($a.StoreId) --source msstore --accept-package-agreements --accept-source-agreements --silent; if (`$LASTEXITCODE -ne 0) { throw ""winget exit `$LASTEXITCODE"" }"
      }
    }
    'capability' {
      $script:caps | Where-Object { $_.StartsWith($a.Prefix) } |
        ForEach-Object { Remove-WindowsCapability -Online -Name $_ | Out-Null }
    }
    'feature' {
      # Gone with its capability (WindowsMediaPlayer goes with Media.WindowsMediaPlayer).
      if (Get-WindowsOptionalFeature -Online -FeatureName $a.Name -ErrorAction SilentlyContinue) {
        Disable-WindowsOptionalFeature -Online -FeatureName $a.Name -NoRestart | Out-Null
      }
    }
    'custom' { & $a.Set }
  }
}

# --------------------------------------------------------------- profile --
# The VM profile this guest is (winvm writes C:\ProgramData\winvm\profile.txt);
# entries may differ by profile.
$vmProfile = 'default'
if (Test-Path 'C:\ProgramData\winvm\profile.txt') { $vmProfile = (Get-Content 'C:\ProgramData\winvm\profile.txt' -Raw).Trim() }

# The sign-in's LSA secret DefaultPassword, read and removed (sign-in entries).
$winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
function Use-Lsa {
  if ('WinvmLsa' -as [type]) { return }
  Add-Type @"
using System; using System.Runtime.InteropServices;
public static class WinvmLsa {
  [StructLayout(LayoutKind.Sequential)] public struct UNICODE_STRING { public ushort Length, MaximumLength; public IntPtr Buffer; }
  [StructLayout(LayoutKind.Sequential)] public struct OBJECT_ATTRIBUTES { public int Length; public IntPtr RootDirectory, ObjectName; public uint Attributes; public IntPtr SecurityDescriptor, SecurityQualityOfService; }
  [DllImport("advapi32.dll")] static extern uint LsaOpenPolicy(IntPtr system, ref OBJECT_ATTRIBUTES oa, uint access, out IntPtr handle);
  [DllImport("advapi32.dll")] static extern uint LsaRetrievePrivateData(IntPtr h, ref UNICODE_STRING key, out IntPtr data);
  [DllImport("advapi32.dll")] static extern uint LsaStorePrivateData(IntPtr h, ref UNICODE_STRING key, IntPtr data);
  [DllImport("advapi32.dll")] static extern uint LsaFreeMemory(IntPtr p);
  [DllImport("advapi32.dll")] static extern uint LsaClose(IntPtr h);
  static UNICODE_STRING Str(string s) {
    var u = new UNICODE_STRING(); u.Buffer = Marshal.StringToHGlobalUni(s);
    u.Length = (ushort)(s.Length * 2); u.MaximumLength = (ushort)(s.Length * 2 + 2); return u;
  }
  static IntPtr Open() {
    var oa = new OBJECT_ATTRIBUTES(); oa.Length = Marshal.SizeOf(oa); IntPtr h;
    uint r = LsaOpenPolicy(IntPtr.Zero, ref oa, 0x000F0FFF, out h);
    if (r != 0) throw new Exception("LsaOpenPolicy 0x" + r.ToString("x")); return h;
  }
  public static bool Has(string name) {
    IntPtr h = Open();
    try {
      var k = Str(name); IntPtr d; uint r = LsaRetrievePrivateData(h, ref k, out d);
      if (r == 0) { LsaFreeMemory(d); return true; }
      if (r == 0xC0000034) return false;
      throw new Exception("LsaRetrievePrivateData 0x" + r.ToString("x"));
    } finally { LsaClose(h); }
  }
  public static void Remove(string name) {
    IntPtr h = Open();
    try {
      var k = Str(name); uint r = LsaStorePrivateData(h, ref k, IntPtr.Zero);
      if (r != 0 && r != 0xC0000034) throw new Exception("LsaStorePrivateData 0x" + r.ToString("x"));
    } finally { LsaClose(h); }
  }
}
"@
}
