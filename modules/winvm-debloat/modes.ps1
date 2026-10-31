# ---------------------------------------------------- after a Windows update --
# A copy of this script in C:\ProgramData\winvm (writable by administrators
# only: the task runs it elevated) and a task that runs it at the user's logon
# with -Mode auto: when the OS build differs from the last clean run, apply.
$autoDir = 'C:\ProgramData\winvm'
$autoScript = "$autoDir\winvm-debloat.ps1"
$autoArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $autoScript -Mode auto"
Custom 'task \winvm\debloat-after-update (current copy of this script)' {
  $t = Get-ScheduledTask -TaskPath '\winvm\' -TaskName 'debloat-after-update' -ErrorAction SilentlyContinue
  (Test-Path $autoScript) -and ((Get-Content -Raw $autoScript) -eq $self) -and $t -and
    ($t.Actions[0].Arguments -eq $autoArgs) -and ($t.State -ne 'Disabled') -and
    ($t.Triggers[0].UserId -eq $me)  # the account name changes with the computer name
} {
  New-Item -ItemType Directory -Path $autoDir -Force | Out-Null
  icacls.exe $autoDir /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
  [System.IO.File]::WriteAllText($autoScript, $self, [System.Text.Encoding]::ASCII)
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $autoArgs
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User $me
  $principal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Highest
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 2)
  Register-ScheduledTask -TaskPath '\winvm\' -TaskName 'debloat-after-update' -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force | Out-Null
}

# ------------------------------------------------------------------ modes --
function Test-All {
  Read-State
  $bad = 0
  foreach ($e in $entries) {
    $ok = $false
    try { $ok = [bool](Test-Entry $e) } catch { $ok = $false }
    if ($ok) { Out-Line ('ok       ' + $e.Name) } else { Out-Line ('differs  ' + $e.Name); $bad++ }
  }
  Out-Line ('{0} entries, {1} differ' -f $entries.Count, $bad)
  return $bad
}

function Invoke-Apply {
  Read-State
  $hkcu = $false
  foreach ($e in $entries) {
    $ok = $false
    try { $ok = [bool](Test-Entry $e) } catch { $ok = $false }
    if ($ok) { continue }
    try {
      Set-Entry $e
      Out-Line ('applied  ' + $e.Name)
      if ($e.Name -like '*HKCU:*') { $hkcu = $true }
    } catch {
      Out-Line ('failed   ' + $e.Name + ': ' + $_.Exception.Message)
    }
  }
  # Explorer reads the HKCU values again when it restarts (Windows restarts it).
  if ($hkcu) { Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force }
}

function Remove-Contents([string]$dir, [string[]]$keep = @()) {
  if (-not (Test-Path $dir)) { return }
  Get-ChildItem -Path $dir -Force -ErrorAction SilentlyContinue |
    Where-Object { $n = $_.Name; -not ($keep | Where-Object { $n -like $_ }) } |
    ForEach-Object { Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
}

function Invoke-Clean {
  $before = (Get-Volume -DriveLetter C).SizeRemaining
  Out-Line 'clean: recycle bin, temp folders'
  Clear-RecycleBin -DriveLetter C -Force -ErrorAction SilentlyContinue
  Remove-Contents $env:TEMP
  Remove-Contents 'C:\Windows\Temp' @('winvm-*')
  Out-Line 'clean: Windows Error Reporting queue and archive, Delivery Optimization cache'
  Remove-Contents 'C:\ProgramData\Microsoft\Windows\WER\ReportQueue'
  Remove-Contents 'C:\ProgramData\Microsoft\Windows\WER\ReportArchive'
  Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue
  $pending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
  if ($pending) {
    Out-Line 'clean: an update is pending a restart; SoftwareDistribution\Download and the component store left alone'
  } else {
    Out-Line 'clean: SoftwareDistribution\Download'
    Stop-Service -Name wuauserv, bits -Force -ErrorAction SilentlyContinue
    Remove-Contents 'C:\Windows\SoftwareDistribution\Download'
    Start-Service -Name wuauserv, bits -ErrorAction SilentlyContinue
  }
  # Caches Disk Cleanup would empty, removed directly: cleanmgr.exe is a GUI
  # program and hung in the SSH session (2026-10-11). Never the Downloads
  # folder or the system crash dumps (debugging).
  Out-Line 'clean: shader, browser-engine and thumbnail caches, setup and upgrade leftovers'
  Remove-Contents "$env:LOCALAPPDATA\D3DSCache"
  Remove-Contents "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"
  Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Filter 'thumbcache_*.db' -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
  Remove-Contents 'C:\Windows\Logs\CBS' @('CBS.log')
  Remove-Contents 'C:\Windows\Panther\UnattendGC'
  foreach ($d in 'C:\$Windows.~BT', 'C:\$Windows.~WS', 'C:\Windows.old') {
    if (Test-Path $d) { Out-Line "clean: $d is left to Storage Sense (it needs ownership changes)" }
  }
  if (-not $pending) {
    Out-Line 'clean: DISM /StartComponentCleanup (no /ResetBase)'
    dism.exe /English /Online /Cleanup-Image /StartComponentCleanup | Select-String -Pattern 'error|completed' | ForEach-Object { Out-Line ('dism: ' + $_.Line.Trim()) }
  }
  # Reserved storage off: refused while servicing is in progress (0x800f0975),
  # so it is a cleanup step to retry, not declared state (2026-10-11).
  $rs = dism.exe /English /Online /Set-ReservedStorageState /State:Disabled
  if ($LASTEXITCODE -eq 0) { Out-Line 'clean: reserved storage disabled' }
  else { Out-Line ('clean: reserved storage left on for now: ' + (($rs | Select-String 'Error') -join ' ')) }
  Out-Line 'clean: TRIM (gives the space back to disk.qcow2)'
  # In a --scratch session (QEMU -snapshot) the retrim fails with a CRC data
  # error (0x80070017) while both volumes stay healthy (2026-10-11): logged, not fatal.
  try { Optimize-Volume -DriveLetter C -ReTrim -ErrorAction Stop }
  catch { Out-Line ('clean: TRIM failed: ' + $_.Exception.Message) }
  $after = (Get-Volume -DriveLetter C).SizeRemaining
  Out-Line ('clean: C: free {0:N1} GB -> {1:N1} GB' -f ($before / 1GB), ($after / 1GB))
}

function Get-Build {
  $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
  return '{0}.{1}' -f $cv.CurrentBuild, $cv.UBR
}

# Apply only when the build changed since the last run that left nothing
# differing; the build is recorded only then, so a failed entry is retried at
# the next logon.
$marker = 'HKLM:\SOFTWARE\winvm'
function Invoke-ApplyAndRecord {
  Invoke-Apply
  $bad = Test-All
  if ($bad -eq 0) {
    if (-not (Test-Path $marker)) { New-Item -Path $marker -Force | Out-Null }
    New-ItemProperty -Path $marker -Name DebloatedBuild -Value (Get-Build) -PropertyType String -Force | Out-Null
  }
  return $bad
}
function Invoke-Auto {
  $build = Get-Build
  if ((Get-RegValue $marker 'DebloatedBuild') -eq $build) { return }
  Out-Line "build $build differs from the last clean run; applying"
  Invoke-ApplyAndRecord | Out-Null
}

# Before OOBE (the answer file's specialize pass, as SYSTEM, no user yet): only
# entries that need no user session. Registry values (the HKCU ones written into
# the default user's hive, which the user's profile is created from), services,
# provisioned Store apps (so not even the first profile gets them). The rest,
# and a check of all of it, comes at the first logon (-Mode apply).
function Invoke-Specialize {
  $hive = 'HKU\winvm-default'
  reg.exe load $hive 'C:\Users\Default\NTUSER.DAT' | Out-Null
  try {
    $prov = @(Get-AppxProvisionedPackage -Online)
    foreach ($e in $entries) {
      $m = $e
      if ($e.Kind -in 'reg', 'regabsent' -and $e.A.Path -like 'HKCU:\*') {
        $a = $e.A.Clone()
        $a.Path = 'Registry::HKEY_USERS\winvm-default\' + $e.A.Path.Substring(6)
        $m = [pscustomobject]@{ Kind = $e.Kind; Name = $e.Name; A = $a }
      }
      try {
        if ($m.Kind -in 'service', 'userservice') {
          # The Start value only: nothing to stop before OOBE, and Disabled
          # takes effect from the first boot.
          $svc = "HKLM:\SYSTEM\CurrentControlSet\Services\$($m.A.Name)"
          if ((Test-Path $svc) -and ((Get-RegValue $svc 'Start') -ne 4)) {
            Set-ItemProperty -Path $svc -Name Start -Value 4
            Out-Line ('applied  ' + $m.Name)
          }
        } elseif ($m.Kind -in 'reg', 'regabsent') {
          if (-not (Test-Entry $m)) { Set-Entry $m; Out-Line ('applied  ' + $m.Name) }
        } elseif ($m.Kind -eq 'appx') {
          $p = @($prov | Where-Object DisplayName -eq $m.A.Name)
          if ($p) { $p | Remove-AppxProvisionedPackage -Online | Out-Null; Out-Line ('applied  ' + $m.Name) }
        }
      } catch {
        Out-Line ('failed   ' + $m.Name + ': ' + $_.Exception.Message)
      }
    }
  } finally {
    # The hive stays loaded while anything holds a handle to it.
    [gc]::Collect(); [gc]::WaitForPendingFinalizers()
    reg.exe unload $hive | Out-Null
  }
}

Out-Line "winvm-debloat -Mode $Mode"
switch ($Mode) {
  'specialize' { Invoke-Specialize }
  'auto' { Invoke-Auto }
  'check' { if ((Test-All) -gt 0) { exit 1 } }
  'apply' { if ((Invoke-ApplyAndRecord) -gt 0) { exit 1 } }
  'clean' { Invoke-Clean }
}
