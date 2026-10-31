# ------------------------------------------------------------- Store apps --
@(
  'Clipchamp.Clipchamp', 'Microsoft.BingNews', 'Microsoft.BingSearch', 'Microsoft.BingWeather',
  'Microsoft.GamingApp', 'Microsoft.GetHelp', 'Microsoft.MicrosoftOfficeHub',
  'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.MicrosoftStickyNotes', 'Microsoft.OutlookForWindows',
  'Microsoft.PowerAutomateDesktop', 'Microsoft.Todos', 'Microsoft.WindowsAlarms', 'Microsoft.WindowsCamera',
  'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsSoundRecorder', 'Microsoft.Xbox.TCUI',
  'Microsoft.XboxGamingOverlay', 'Microsoft.XboxIdentityProvider', 'Microsoft.XboxSpeechToTextOverlay',
  'Microsoft.YourPhone', 'Microsoft.ZuneMusic', 'MicrosoftCorporationII.QuickAssist',
  'MicrosoftWindows.Client.WebExperience', 'Microsoft.WidgetsPlatformRuntime', 'MicrosoftWindows.CrossDevice',
  'MSTeams', 'Microsoft.Windows.DevHome',
  'Microsoft.AV1VideoExtension', 'Microsoft.AVCEncoderVideoExtension', 'Microsoft.HEIFImageExtension',
  'Microsoft.HEVCVideoExtension', 'Microsoft.MPEG2VideoExtension', 'Microsoft.RawImageExtension',
  'Microsoft.VP9VideoExtensions', 'Microsoft.WebMediaExtensions', 'Microsoft.WebpImageExtension'
) | ForEach-Object { Appx $_ }
# Kept: WindowsStore, StorePurchaseApp, DesktopAppInstaller (winget), SecHealthUI
# (Defender), ApplicationCompatibilityEnhancements, MicrosoftEdge.Stable,
# StartExperiencesApp (part of Start). The classic notepad.exe stays (capability below).

# -------------------------------------------------------------- languages --
# The installed UI language only (the ISO's), with the keyboard layout of
# locale.input as its keyboard (<lcid>:<layout>): no other language in the
# list, so Windows has no reason to install their features again. Formats
# need no language package.
$ui = [Globalization.CultureInfo]::InstalledUICulture
$uiTag = $ui.Name
$keyboard = '{0:x4}:{1}' -f $ui.LCID, $winvmKeyboard
Custom "languages: $uiTag only, keyboard $winvmKeyboard" {
  $l = @(Get-WinUserLanguageList)
  ($l.Count -eq 1) -and ($l[0].LanguageTag -eq $uiTag) -and
    ((@($l[0].InputMethodTips) -join ',') -eq $keyboard) -and
    ((Get-WinDefaultInputMethodOverride).InputMethodTip -eq $keyboard)
} {
  $l = New-WinUserLanguageList $uiTag
  $l[0].InputMethodTips.Clear()
  $l[0].InputMethodTips.Add($keyboard)
  Set-WinUserLanguageList -LanguageList $l -Force
  Set-WinDefaultInputMethodOverride -InputTip $keyboard
  # The sign-in screen and new profiles get the same keyboard.
  Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true
}

# ------------------------------------------- capabilities, optional features --
@(
  'App.StepsRecorder', 'Browser.InternetExplorer', 'Hello.Face.', 'MathRecognizer', 'Media.WindowsMediaPlayer',
  # Every language feature except the UI language's basics and OCR:
  # handwriting, speech, text to speech in any language. Windows installs OCR
  # for a listed language by itself (it came back after a restart,
  # 2026-10-11), and the Snipping Tool uses it for text in screenshots, so the
  # UI language's stays. Other languages' basics and OCR are the host's to list.
  'Language.Handwriting~~~', 'Language.Speech~~~', 'Language.TextToSpeech~~~'
) | ForEach-Object { Capability $_ }
@(
  'Microsoft.Wallpapers.Extended', 'Microsoft.Windows.PowerShell.ISE', 'Print.Management.Console',
  'OneCoreUAP.OneSync', 'Microsoft.Windows.Ethernet.Client.', 'Microsoft.Windows.Wifi.Client.'
) | ForEach-Object { Capability $_ }

# Also (2026-10-11): the RDP client (nothing is reached over RDP from the
# guest), Remote Differential Compression, printing with Print to PDF (the
# Spooler is off, so they did nothing), the Camera Class Extension framework
# (new in 26H2; no camera in the VM).
@('WorkFolders-Client', 'WindowsMediaPlayer', 'Printing-Foundation-InternetPrinting-Client', 'SmbDirect',
  'Microsoft-RemoteDesktopConnection', 'MSRDC-Infrastructure', 'Printing-PrintToPDFServices-Features',
  'Printing-Foundation-Features', 'Microsoft-Windows-Camera-CCX-Deployment') |
  ForEach-Object { Feature $_ }

# --------------------------------------------------------------- UI noise --
$cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$desktop = 'HKCU:\Control Panel\Desktop'
$advanced = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
@('ContentDeliveryAllowed', 'FeatureManagementEnabled', 'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled',
  'PreInstalledAppsEverEnabled', 'SilentInstalledAppsEnabled', 'SoftLandingEnabled', 'SystemPaneSuggestionsEnabled',
  'RotatingLockScreenEnabled', 'RotatingLockScreenOverlayEnabled') | ForEach-Object { Reg $cdm $_ 0 }
# Every SubscribedContent-<id>Enabled Windows has created, whatever the ids are.
Custom "reg $cdm\SubscribedContent-*Enabled = 0" {
  $item = Get-ItemProperty -Path $cdm -ErrorAction SilentlyContinue
  -not ($item.PSObject.Properties | Where-Object { $_.Name -like 'SubscribedContent-*Enabled' -and $_.Value -ne 0 })
} {
  $item = Get-ItemProperty -Path $cdm
  $item.PSObject.Properties | Where-Object { $_.Name -like 'SubscribedContent-*Enabled' } |
    ForEach-Object { Set-ItemProperty -Path $cdm -Name $_.Name -Value 0 }
}

Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
# (No Dsh\AllowNewsAndInterests policy: Windows locks that key, "unauthorized
# operation" on 2026-10-11; Widgets are removed as an app above.)
Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
# Suggestions in Settings and Start, "Get even more out of Windows", tips,
# widgets on the lock screen, "recently added" in Start.
@('338393', '353694', '353696') | ForEach-Object { Reg $cdm "SubscribedContent-$($_)Enabled" 0 }
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested' 'Enabled' 0
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen' 'AutoSelectWidgetsOnLockScreen' 0
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'HideRecentlyAddedApps' 1
# Windows welcome experience after updates, Spotlight on the desktop.
Reg $cdm 'SubscribedContent-310093Enabled' 0
Reg 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsSpotlightWindowsWelcomeExperience' 1
Reg 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableSpotlightCollectionOnDesktop' 1

# Explorer: opens on This PC; no Gallery, no recent files or frequent folders
# in Quick access, no sync-provider notifications (OneDrive ads); the classic
# context menu (no "Show more options").
Reg $advanced 'LaunchTo' 1
Reg $advanced 'ShowSyncProviderNotifications' 0
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowRecent' 0
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowFrequent' 0
Reg 'HKCU:\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}' 'System.IsPinnedToNameSpaceTree' 0
Reg 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' '(default)' '' 'String'

# Search stays local: no search highlights, no cloud (account) search, no history.
$searchSettings = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'
Reg $searchSettings 'IsDynamicSearchBoxEnabled' 0
Reg $searchSettings 'IsMSACloudSearchEnabled' 0
Reg $searchSettings 'IsAADCloudSearchEnabled' 0
Reg $searchSettings 'IsDeviceSearchHistoryEnabled' 0
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'EnableDynamicContentInWSB' 0
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCloudSearch' 0

# Windows Security: only critical notifications; no "sign in with a Microsoft account".
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications' 'DisableEnhancedNotifications' 1
Reg 'HKCU:\Software\Microsoft\Windows Security Health\State' 'AccountProtection_MicrosoftAccount_Disconnected' 1
# "Action recommended" in Device security (26H2): "Sign in with Microsoft for
# enhanced security" (device encryption); its Dismiss writes this value
# (captured 2026-10-11). Nothing protective depends on a Microsoft account here.
Reg 'HKCU:\Software\Microsoft\Windows Security Health\State' 'Hardware_DataEncryption_AddMsa' 0
# Microsoft account nags in Settings ("Back up your PC to Microsoft account",
# "Sign in to get the most out of Windows", the Microsoft 365 and Rewards
# tiles) and Start, seen on the fresh default guest (2026-10-17): Settings >
# Privacy > General "Show me notifications in the Settings app" off, and the
# policy "Turn off cloud consumer account state content".
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SystemSettings\AccountNotifications' 'EnableAccountNotifications' 0
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 1
# Settings opens on System: no Home page, the main place of its Microsoft
# account and Microsoft 365 cards (policy "Settings Page Visibility"). The
# Microsoft 365 tile on the System page and the account card and Rewards on
# Accounts have no supported switch (2026-10-17; "Block Microsoft accounts",
# NoConnectedUser=3, tried, no effect) and stay.
Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'SettingsPageVisibility' 'hide:home' 'String'
# No cloud-promoted pins or content in Start for new profiles (WhatsApp,
# LinkedIn and the like among a fresh install's pins).
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 1

# Game Bar and background recording off (Game Mode stays).
Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
Reg 'HKCU:\Software\Microsoft\GameBar' 'UseNexusForGameBarEnabled' 0
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0

# Resume (continue on this PC what was open on a phone or in OneDrive): off,
# the values Settings > Apps > Resume writes (2026-10-11).
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration' 'IsResumeAllowed' 0
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration' 'IsOneDriveResumeAllowed' 0

# Nearby sharing off, no promoted apps in the share sheet (2026-10-11).
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CDP' 'NearShareChannelUserAuthzPolicy' 0
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CDP' 'EnablePromotionalAppsForShare' 0

# Clipboard: local history (Win+V) on, no sync across devices.
Reg 'HKCU:\Software\Microsoft\Clipboard' 'EnableClipboardHistory' 1
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'AllowCrossDeviceClipboard' 0

# Start and taskbar pins: pinned by hand once and captured into the host's
# layoutDir; winvm copies the profile's to C:\ProgramData\winvm\layout.
# Restored once per Windows user profile (a marker in HKCU), so later changes
# by hand are never fought. (Policies written straight to the registry --
# ConfigureStartPins, a taskbar layout file -- do nothing useful without MDM.)
$layout = 'C:\ProgramData\winvm\layout'
# A VM profile without captured pins (winvm copies none) keeps Windows' own.
Custom 'pins: Start and taskbar restored once per profile' {
  ((Get-RegValue 'HKCU:\Software\winvm' 'LayoutRestored') -eq 1) -or -not (Test-Path "$layout\start2.bin")
} {
  if (-not (Test-Path "$layout\start2.bin")) { throw "$layout missing (winvm debloat copies it)" }
  $startState = "$env:LOCALAPPDATA\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState"
  New-Item -ItemType Directory -Path $startState -Force | Out-Null
  Get-Process -Name StartMenuExperienceHost -ErrorAction SilentlyContinue | Stop-Process -Force
  Copy-Item "$layout\start2.bin" $startState -Force
  $pinned = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
  New-Item -ItemType Directory -Path $pinned -Force | Out-Null
  Copy-Item "$layout\taskbar\*.lnk" $pinned -Force
  $tb = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband'
  if (-not (Test-Path $tb)) { New-Item -Path $tb -Force | Out-Null }
  $values = Get-Content -Raw "$layout\taskband.json" | ConvertFrom-Json
  foreach ($v in $values.PSObject.Properties) {
    $data = $v.Value.value
    if ($v.Value.kind -eq 'Binary') { $data = [Convert]::FromBase64String($data) }
    New-ItemProperty -Path $tb -Name $v.Name -Value $data -PropertyType $v.Value.kind -Force | Out-Null
  }
  Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force
  if (-not (Test-Path 'HKCU:\Software\winvm')) { New-Item -Path 'HKCU:\Software\winvm' -Force | Out-Null }
  New-ItemProperty -Path 'HKCU:\Software\winvm' -Name LayoutRestored -Value 1 -PropertyType DWord -Force | Out-Null
}

# AI features: Copilot, Recall, Click to Do, AI in Notepad.
Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement' 0
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableClickToDo' 1
Reg 'HKLM:\SOFTWARE\Policies\WindowsNotepad' 'DisableAIFeatures' 1

# Edge stays installed (WebView2 is separate); it only stops starting itself.
$edgeRun = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
Custom "reg $edgeRun\MicrosoftEdgeAutoLaunch_* absent" {
  $item = Get-ItemProperty -Path $edgeRun -ErrorAction SilentlyContinue
  -not ($item.PSObject.Properties | Where-Object { $_.Name -like 'MicrosoftEdgeAutoLaunch_*' })
} {
  $item = Get-ItemProperty -Path $edgeRun
  $item.PSObject.Properties | Where-Object { $_.Name -like 'MicrosoftEdgeAutoLaunch_*' } |
    ForEach-Object { Remove-ItemProperty -Path $edgeRun -Name $_.Name }
}
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'StartupBoostEnabled' 0
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'BackgroundModeEnabled' 0
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'HideFirstRunExperience' 1
# Edge debloated (2026-10-11); SmartScreen, typosquatting checks and updates stay.
$edge = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
@{
  HubsSidebarEnabled = 0; Microsoft365CopilotChatIconEnabled = 0; CopilotPageContext = 0; ComposeInlineEnabled = 0
  EdgeShoppingAssistantEnabled = 0; ShowRecommendationsEnabled = 0; ShowMicrosoftRewards = 0
  SpotlightExperiencesAndRecommendationsEnabled = 0; PromotionalTabsEnabled = 0; EdgeCollectionsEnabled = 0
  EdgeFollowEnabled = 0; NewTabPageContentEnabled = 0; NewTabPageQuickLinksEnabled = 0
  NewTabPageHideDefaultTopSites = 1; NewTabPageAllowedBackgroundTypes = 3; PersonalizationReportingEnabled = 0
  DiagnosticData = 0; UserFeedbackAllowed = 0; AlternateErrorPagesEnabled = 0; DefaultBrowserSettingEnabled = 0
  ConfigureDoNotTrack = 1
}.GetEnumerator() | Sort-Object Name | ForEach-Object { Reg $edge $_.Name $_.Value }
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' 'CreateDesktopShortcutDefault' 0
Custom 'edge desktop shortcut absent' {
  -not (Test-Path 'C:\Users\Public\Desktop\Microsoft Edge.lnk') -and -not (Test-Path "$env:USERPROFILE\Desktop\Microsoft Edge.lnk")
} {
  Remove-Item -Force -ErrorAction SilentlyContinue 'C:\Users\Public\Desktop\Microsoft Edge.lnk', "$env:USERPROFILE\Desktop\Microsoft Edge.lnk"
}

# OneDrive: its per-user copy uninstalled, the setup that would bring it back
# for LocalService and NetworkService gone, sync blocked by policy.
Custom 'onedrive uninstalled' {
  -not (Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe") -and
  -not (Test-Path 'C:\Program Files\Microsoft OneDrive\OneDrive.exe')
} {
  Get-Process -Name OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force
  $setup = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\OneDrive" -Filter OneDriveSetup.exe -Recurse -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
  if (-not $setup) { $setup = 'C:\Windows\System32\OneDriveSetup.exe' }
  Start-Process -Wait -FilePath $setup -ArgumentList '/uninstall'
}
RegAbsent 'Registry::HKEY_USERS\S-1-5-19\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'OneDriveSetup'
RegAbsent 'Registry::HKEY_USERS\S-1-5-20\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'OneDriveSetup'
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1

# -------------------------------------------------------------- telemetry --
# AllowTelemetry 0 is honoured on Enterprise/Education only; Pro reads it as 1.
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 1
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 0
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1
Reg 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1
Reg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1
Reg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
Reg 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0
Reg 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' 'DisableLocation' 1
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
Service 'DiagTrack'
Service 'dmwappushservice'
# Taken from Get-ScheduledTask on build 26300 (2026-10-11); a missing task counts as ok.
Task '\Microsoft\Windows\Application Experience\' 'Microsoft Compatibility Appraiser Exp'
Task '\Microsoft\Windows\Application Experience\' 'MareBackup'
Task '\Microsoft\Windows\Autochk\' 'Proxy'
Task '\Microsoft\Windows\Customer Experience Improvement Program\' 'Consolidator'
Task '\Microsoft\Windows\Customer Experience Improvement Program\' 'UsbCeip'
Task '\Microsoft\Windows\DiskDiagnostic\' 'Microsoft-Windows-DiskDiagnosticDataCollector'
Task '\Microsoft\Windows\Feedback\Siuf\' 'DmClient'
Task '\Microsoft\Windows\Feedback\Siuf\' 'DmClientOnScenarioDownload'
Task '\Microsoft\Windows\Maps\' 'MapsToastTask'

# ------------------------------------------------------- resources at idle --
Service 'SysMain'
Service 'WSearch'
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground' 2
# No printing in the VM (2026-10-11): Print to PDF goes with it.
Service 'Spooler'
Service 'PrintNotify'
# Services with nothing to do in this VM (2026-10-11): maps, location,
# compatibility inventory (telemetry), AI components, "optimized experiences",
# link tracking, SMB server (the client stays), NetBIOS and network discovery
# (the guest sits behind QEMU's NAT), IPv6 transition, the compatibility
# assistant, radios, display brightness, cloud backup.
@('MapsBroker', 'lfsvc', 'InventorySvc', 'WSAIFabricSvc', 'whesvc', 'TrkWks', 'LanmanServer', 'lmhosts',
  'fdPHost', 'FDResPub', 'SSDPSRV', 'NcdAutoSetup', 'iphlpsvc', 'PcaSvc', 'RmSvc',
  'DisplayEnhancementService') | ForEach-Object { Service $_ }
# SensorService stays at its default (manual, started on demand): Settings >
# System > Power crashed without it (RPC 0x800706D9, endpoint not registered;
# tested 2026-10-17: the page opened with it alone of the disabled services).
Custom 'service SensorService manual (Settings > Power needs it)' {
  (Get-Service -Name SensorService -ErrorAction SilentlyContinue).StartType -ne 'Disabled'
} {
  Set-Service -Name SensorService -StartupType Manual
}
UserService 'CloudBackupRestoreSvc'
# On trial since 2026-10-11: dropped again if Start, Settings, notifications
# or the taskbar misbehave without them.
Service 'CDPSvc'
UserService 'CDPUserSvc'
Service 'DPS'
UserService 'PimIndexMaintenanceSvc'
UserService 'UnistoreSvc'
UserService 'UserDataSvc'

# High performance, never sleep (a sleeping guest under QEMU is no use), and
# no USB selective suspend: a lent device must not be suspended in the middle
# of its work.
$highPerf = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$usbSub = '2a737441-1930-4402-8d77-b2bebba308a3'; $usbSuspend = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
function Get-PowerIndex([string]$sub, [string]$setting) {
  $q = powercfg.exe /query $highPerf $sub $setting | Select-String 'Current AC Power Setting Index: (0x[0-9a-f]+)'
  if ($q) { return [Convert]::ToInt32($q.Matches[0].Groups[1].Value, 16) } else { return $null }
}
Custom 'power: High performance, never sleep, no USB selective suspend' {
  ((powercfg.exe /getactivescheme) -match $highPerf) -and
    ((Get-PowerIndex $usbSub $usbSuspend) -eq 0) -and
    ((Get-PowerIndex 'SUB_SLEEP' 'STANDBYIDLE') -eq 0)
} {
  powercfg.exe /setacvalueindex $highPerf $usbSub $usbSuspend 0
  powercfg.exe /change -standby-timeout-ac 0
  powercfg.exe /setacvalueindex $highPerf SUB_SLEEP STANDBYIDLE 0
  powercfg.exe /setactive $highPerf
}

# No USB selective suspend anywhere. The power plan's setting (above) does not
# reach HID devices: they have their own per-device switch, so Windows put
# QEMU's USB keyboard (VID_0627&PID_0001) to sleep after a minute idle, QEMU did
# not wake it, and the keyboard died while the mouse kept working (2026-10-11).
# DisableSelectiveSuspend is the global switch (every device, also one lent
# later through winvm usb); the per-device values fix the QEMU devices now.
Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\USB' 'DisableSelectiveSuspend' 1
$qemuHid = 'HKLM:\SYSTEM\CurrentControlSet\Enum\USB\VID_0627&PID_0001'
Custom 'QEMU USB keyboard and tablet: no selective suspend' {
  -not (Get-ChildItem $qemuHid -ErrorAction SilentlyContinue | Where-Object {
    $dp = Join-Path $_.PSPath 'Device Parameters'
    ((Get-RegValue $dp 'SelectiveSuspendEnabled') -ne 0) -or ((Get-RegValue $dp 'EnhancedPowerManagementEnabled') -ne 0)
  })
} {
  Get-ChildItem $qemuHid | ForEach-Object {
    $dp = Join-Path $_.PSPath 'Device Parameters'
    Set-ItemProperty $dp -Name SelectiveSuspendEnabled -Value 0 -Type DWord
    Set-ItemProperty $dp -Name EnhancedPowerManagementEnabled -Value 0 -Type DWord
    pnputil.exe /restart-device "USB\VID_0627&PID_0001\$($_.PSChildName)" | Out-Null
  }
}

# ------------------------------------------------------------------- name --
# computerName, also for a guest installed under another name. Not part of the
# hardware identity, so activation is unaffected. Takes effect at the next
# restart; the pending name counts, so it is not renamed twice.
Custom "computer name $winvmComputerName (after a restart)" {
  (Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' 'ComputerName') -eq $winvmComputerName.ToUpperInvariant()
} {
  Rename-Computer -NewName $winvmComputerName -Force -WarningAction SilentlyContinue
}

# ------------------------------------------------------------------- RDP --
# Off (2026-10-11): the desktop goes through SPICE, scripts and files
# through SSH; no RDP client is used. Connections refused, the firewall group
# closed; the services keep their default (manual) start.
Reg 'HKLM:\System\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 1
Custom 'firewall: Remote Desktop rules disabled' {
  -not (Get-NetFirewallRule -Group '@FirewallAPI.dll,-28752' -ErrorAction SilentlyContinue | Where-Object Enabled -eq 'True')
} {
  Disable-NetFirewallRule -Group '@FirewallAPI.dll,-28752'
}

# ---------------------------------------------------------------- sign-in --
# A profile with autoLogon signs in by itself (a throw-away session must not
# stop at the sign-in screen). The password stays an LSA secret (never the
# registry); winvm --profile <name> debloat stores it from the password file
# through SSH stdin, and on a fresh install it is the one setup left there.
# Every other profile asks for the password at every sign-in. The answer file
# asks for one auto logon (the first-logon setup), but setup left
# AutoAdminLogon=1 with the password as the LSA secret DefaultPassword (not in
# the registry), so a fresh install signed in by itself at every boot
# (2026-10-17). Both cleared; winvm finish cleans only the clear-text answer
# files.
if ($winvmAutoLogon -contains $vmProfile) {
  Custom "sign-in: auto logon as $winvmUser ($vmProfile profile)" {
    Use-Lsa
    ((Get-RegValue $winlogon 'AutoAdminLogon') -eq '1') -and ((Get-RegValue $winlogon 'DefaultUserName') -eq $winvmUser) -and
      ($null -eq (Get-RegValue $winlogon 'AutoLogonCount')) -and ($null -eq (Get-RegValue $winlogon 'DefaultPassword')) -and
      [WinvmLsa]::Has('DefaultPassword')
  } {
    Use-Lsa
    if (-not [WinvmLsa]::Has('DefaultPassword')) {
      throw "no stored password: winvm --profile $vmProfile debloat stores it from the host"
    }
    Set-ItemProperty -Path $winlogon -Name AutoAdminLogon -Value '1' -Type String
    Set-ItemProperty -Path $winlogon -Name DefaultUserName -Value $winvmUser -Type String
    Remove-ItemProperty -Path $winlogon -Name AutoLogonCount -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $winlogon -Name DefaultPassword -ErrorAction SilentlyContinue
  }
} else {
  Custom 'sign-in: no auto logon, no stored password' {
    Use-Lsa
    ((Get-RegValue $winlogon 'AutoAdminLogon') -ne '1') -and ($null -eq (Get-RegValue $winlogon 'DefaultPassword')) -and
      -not [WinvmLsa]::Has('DefaultPassword')
  } {
    Use-Lsa
    Set-ItemProperty -Path $winlogon -Name AutoAdminLogon -Value '0' -Type String
    Remove-ItemProperty -Path $winlogon -Name DefaultPassword -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $winlogon -Name AutoLogonCount -ErrorAction SilentlyContinue
    [WinvmLsa]::Remove('DefaultPassword')
  }
}

# ------------------------------------------------------------- BitLocker --
# Off for good (2026-10-17). Windows 11 turned on device encryption by
# itself (a TPM and Secure Boot are present; no Microsoft account needed on
# this build): C: was found part-encrypted on 2026-10-17, its key held only by
# the swtpm state, with no recovery key kept anywhere. The host encrypts its
# own disk, and a BitLocker volume cannot be read or edited from the host
# (libguestfs). The answer file sets PreventDeviceEncryption in specialize, so a
# new install never starts; this decrypts an existing one. Decryption runs in
# the background and survives restarts, so 'in progress' counts as reached.
Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker' 'PreventDeviceEncryption' 1
Custom 'bitlocker: C: decrypted (or decrypting)' {
  (Get-BitLockerVolume -MountPoint 'C:').VolumeStatus -in 'FullyDecrypted', 'DecryptionInProgress'
} {
  Disable-BitLocker -MountPoint 'C:' | Out-Null
}

# ------------------------------------------------------------ Task Manager --
# The host's taskmgrSettings (start page, CPU view, the columns of each tab),
# a captured settings.json that winvm copies to C:\ProgramData\winvm; restored
# once per Windows user profile like the pins, so
# later changes by hand are kept. Task Manager rewrites the file when it exits,
# so it is closed first.
$taskmgrSaved = 'C:\ProgramData\winvm\taskmgr-settings.json'
Custom 'task manager: settings restored once per profile' {
  ((Get-RegValue 'HKCU:\Software\winvm' 'TaskMgrRestored') -eq 1) -or -not (Test-Path $taskmgrSaved)
} {
  Get-Process -Name Taskmgr -ErrorAction SilentlyContinue | Stop-Process -Force
  $dir = "$env:LOCALAPPDATA\Microsoft\Windows\TaskManager"
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  Copy-Item $taskmgrSaved "$dir\settings.json" -Force
  if (-not (Test-Path 'HKCU:\Software\winvm')) { New-Item -Path 'HKCU:\Software\winvm' -Force | Out-Null }
  New-ItemProperty -Path 'HKCU:\Software\winvm' -Name TaskMgrRestored -Value 1 -PropertyType DWord -Force | Out-Null
}

# --------------------------------------------------------- Windows Update --
# Updates stay. No drivers from Windows Update (the VM runs virtio drivers);
# feature updates (the ones that bring apps and settings back) deferred a year.
$wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
Reg $wu 'ExcludeWUDriversInQualityUpdate' 1
Reg $wu 'DeferFeatureUpdates' 1
Reg $wu 'DeferFeatureUpdatesPeriodInDays' 365

# ----------------------------------------------------------- Storage Sense --
# Weekly: temporary files, the recycle bin after 1 day; never the Downloads
# folder. (Windows.old goes by itself 10 days after a feature update.)
$ss = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense'
Reg $ss 'AllowStorageSenseGlobal' 1
Reg $ss 'ConfigStorageSenseGlobalCadence' 7
Reg $ss 'AllowStorageSenseTemporaryFilesCleanup' 1
Reg $ss 'ConfigStorageSenseRecycleBinCleanupThreshold' 1
Reg $ss 'ConfigStorageSenseDownloadsCleanupThreshold' 0

# ---------------------------------------------------------------- network --
# The guest sits behind QEMU's NAT: no LLMNR, mDNS or NetBIOS over TCP/IP
# (nothing to find, nothing to spoof).
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'EnableMulticast' 0
Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'EnableMDNS' 0
$netbt = 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces'
Custom 'NetBIOS over TCP/IP off on every interface' {
  -not (Get-ChildItem $netbt | Where-Object { (Get-RegValue $_.PSPath 'NetbiosOptions') -ne 2 })
} {
  Get-ChildItem $netbt | ForEach-Object { Set-ItemProperty -Path $_.PSPath -Name NetbiosOptions -Value 2 }
}

# ------------------------------------------------- Windows Error Reporting --
# Kept for its local dumps; nothing is sent unasked.
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting\Consent' 'DefaultConsent' 1
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'DontSendAdditionalData' 1
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'DontShowUI' 1

