<#
.SYNOPSIS
    Installs a standard set of business applications on a new Windows PC.

.DESCRIPTION
    Built to cut down the repetitive part of new-PC setup at an MSP.
    Installs Microsoft 365 Apps for business (including classic Outlook), Microsoft
    Teams, Adobe Acrobat, VLC, Google Chrome, Mozilla Firefox, and 7-Zip silently
    and machine-wide.

    Most apps come from the official WinGet repository. Office and Teams are
    downloaded directly from Microsoft instead, because WinGet's packages can't
    install the Business edition of Office or install Teams for every user. Those
    downloads are only run if they carry a valid Microsoft Corporation signature.

    Before installing anything, each app is checked and skipped if it's already there:
      1. Add/Remove Programs (registry): machine-wide installs, 32-bit installs, and
         per-user installs for every signed-in user. This catches apps installed from
         any source, such as Chrome downloaded from google.com.
      2. WinGet's own installed list, by exit code, including alternate package IDs.
      3. For Teams, whether it's already set up for all users.

    Run it through Run-Setup.bat, which handles elevation and execution policy,
    or from an elevated PowerShell window.

.PARAMETER CheckOnly
    Report what is already installed and what would be installed, without
    installing anything. Use this to test detection on a machine.

.EXAMPLE
    .\install-new-pc.ps1 -CheckOnly

.NOTES
    Author : T. Brock Hubbard
    Requires: Windows 10/11 with App Installer (WinGet), administrator rights, internet access
#>

#Requires -RunAsAdministrator

param(
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'

# ---- Apps to install -------------------------------------------------------
# Add or remove entries here to customize the build for a client.
#   Name      : friendly name for the screen and log
#   Id        : WinGet package ID to install. Find IDs with:  winget search <name>
#   AltIds    : (optional) other WinGet IDs that mean "already installed"
#   Match     : regex matched against the program's name in Add/Remove Programs
#   Exclude   : (optional) regex for Add/Remove Programs names to ignore
#   Installer : (optional) 'Office' or 'Teams' to use the direct Microsoft installer
#               instead of WinGet
#   AppxName  : (optional) Windows app package name that means "already installed"
$Apps = @(
    @{ Name      = 'Microsoft 365 Apps for business'
       Installer = 'Office'
       AltIds    = @('Microsoft.Office')
       Match     = '^Microsoft (365|Office)\b'
       Exclude   = 'Add-?in|Viewer|Service Pack|Validation|Compatibility|Click-to-Run|Proofing|Language Pack|Interop|Web Components|Runtime' }
    @{ Name      = 'Microsoft Teams'
       Installer = 'Teams'
       AppxName  = 'MSTeams' }   # the work/school Teams app ("MicrosoftTeams" is the old personal one)
    @{ Name      = 'Adobe Acrobat'
       Id        = 'Adobe.Acrobat.Reader.64-bit'
       AltIds    = @('Adobe.Acrobat.Reader.32-bit', 'Adobe.Acrobat.Pro')
       Match     = '^Adobe Acrobat' }
    @{ Name      = 'VLC media player'
       Id        = 'VideoLAN.VLC'
       Match     = '^VLC media player' }
    @{ Name      = 'Google Chrome'
       Id        = 'Google.Chrome'
       AltIds    = @('Google.Chrome.EXE')   # Chrome downloaded from google.com registers under this ID
       Match     = '^Google Chrome$' }
    @{ Name      = 'Mozilla Firefox'
       Id        = 'Mozilla.Firefox'
       Match     = '^Mozilla Firefox' }
    @{ Name      = '7-Zip'
       Id        = '7zip.7zip'
       Match     = '^7-Zip' }
)

# ---- Office settings -------------------------------------------------------
# Office Deployment Tool configuration. To install a different edition, change the
# Product ID, e.g. O365ProPlusRetail for Microsoft 365 Apps for enterprise.
# Reference: https://config.office.com and
# https://learn.microsoft.com/microsoft-365-apps/deploy/office-deployment-tool-configuration-options
$OfficeConfig = @'
<Configuration>
  <Add OfficeClientEdition="64" Channel="Current">
    <Product ID="O365BusinessRetail">
      <Language ID="MatchOS" />
      <ExcludeApp ID="Groove" />
      <ExcludeApp ID="Lync" />
      <ExcludeApp ID="Teams" />
      <ExcludeApp ID="OutlookForWindows" />
    </Product>
  </Add>
  <Updates Enabled="TRUE" />
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
  <Display Level="None" AcceptEULA="TRUE" />
</Configuration>
'@
# Groove = old OneDrive for Business client, Lync = Skype for Business,
# Teams is installed separately below, OutlookForWindows = "new Outlook" (classic Outlook stays).

# Official Microsoft download links
$OfficeSetupUrl       = 'https://officecdn.microsoft.com/pr/wsus/setup.exe'
$TeamsBootstrapperUrl = 'https://go.microsoft.com/fwlink/?linkid=2243204&clcid=0x409'

# ---- Logging ---------------------------------------------------------------
$LogDir      = Join-Path $env:ProgramData 'NewPCSetup'
$LogFile     = Join-Path $LogDir ("setup-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
$DownloadDir = Join-Path $LogDir 'Downloads'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

function Write-Log {
    param([string]$Message, [string]$Color = 'Gray')
    $line = "[{0:HH:mm:ss}] {1}" -f (Get-Date), $Message
    Write-Host $line -ForegroundColor $Color
    Add-Content -Path $LogFile -Value $line
}

# ---- Console: turn off QuickEdit -------------------------------------------
# In a classic console window, clicking inside it starts a text selection
# ("Select" in the title bar), and the script freezes until a key is pressed.
# During a long install that's easy to do by accident, so turn it off for this
# window only. This doesn't change any system setting and ends when the window closes.
function Disable-QuickEdit {
    if ($env:OS -ne 'Windows_NT') { return }
    try {
        Add-Type -Namespace NewPCSetup -Name Console -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
        $ENABLE_QUICK_EDIT_MODE  = 0x0040
        $ENABLE_EXTENDED_FLAGS   = 0x0080
        $handle = [NewPCSetup.Console]::GetStdHandle(-10)   # console input
        $mode   = 0
        if ([NewPCSetup.Console]::GetConsoleMode($handle, [ref]$mode)) {
            $null = [NewPCSetup.Console]::SetConsoleMode($handle,
                ($mode -band (-bnot $ENABLE_QUICK_EDIT_MODE)) -bor $ENABLE_EXTENDED_FLAGS)
        }
    } catch {
        # Not a classic console (e.g. Windows Terminal, which doesn't freeze on select). Nothing to do.
    }
}

# ---- Installed-app detection -----------------------------------------------
function Resolve-UserName {
    param([string]$Sid)
    try {
        ([System.Security.Principal.SecurityIdentifier]$Sid).Translate(
            [System.Security.Principal.NTAccount]).Value
    } catch {
        $Sid
    }
}

function Get-InstalledPrograms {
    # Everything listed in Add/Remove Programs: 64-bit and 32-bit machine-wide
    # installs, plus per-user installs for each user whose profile is loaded
    # (anyone signed in, including the user who is not running the elevated window).
    $roots = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';             Location = 'machine' }
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Location = 'machine, 32-bit' }
    )
    foreach ($hive in Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue) {
        $sid = $hive.PSChildName
        if ($sid -notmatch '^S-1-5-21-[\d-]+$') { continue }   # real user accounts only
        $roots += @{
            Path  = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Uninstall"
            Location = "per-user, $(Resolve-UserName $sid)"
        }
    }

    foreach ($root in $roots) {
        if (-not (Test-Path $root.Path)) { continue }
        foreach ($key in Get-ChildItem $root.Path -ErrorAction SilentlyContinue) {
            $p = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
            if ($p.DisplayName -and $p.SystemComponent -ne 1) {
                [pscustomobject]@{ DisplayName = $p.DisplayName; Location = $root.Location }
            }
        }
    }
}

function Find-InstalledApp {
    # Returns a short description of where the app was found, or $null if it isn't installed.
    param([hashtable]$App)

    # 1. Add/Remove Programs - catches installs from any source, machine-wide or per-user.
    if ($App.Match) {
        $hit = Get-InstalledPrograms | Where-Object {
            $_.DisplayName -match $App.Match -and
            -not ($App.Exclude -and $_.DisplayName -match $App.Exclude)
        } | Select-Object -First 1
        if ($hit) { return "$($hit.DisplayName) ($($hit.Location))" }
    }

    # 2. Windows app packages (Teams). Counts only if it's set up for all users,
    #    so a copy one user installed doesn't stop it being set up for everyone.
    if ($App.AppxName) {
        try {
            $pkg = Get-AppxProvisionedPackage -Online -ErrorAction Stop |
                   Where-Object { $_.DisplayName -eq $App.AppxName } | Select-Object -First 1
            if ($pkg) { return "$($App.AppxName) app (set up for all users)" }
        } catch { }
    }

    # 3. WinGet's installed list. Uses the exit code (0 = found) instead of parsing
    #    the text table, which truncates and changes with console width.
    foreach ($id in @($App.Id) + @($App.AltIds)) {
        if (-not $id) { continue }
        winget list --id $id --exact --accept-source-agreements *> $null
        if ($LASTEXITCODE -eq 0) { return "WinGet package $id" }
    }

    return $null
}

# ---- Run an installer with a live progress bar -----------------------------
function Invoke-WithProgress {
    # Runs an installer and shows a second progress bar with elapsed time while it
    # runs. Silent installers don't report a percentage, so this bar shows the install
    # is still working, not % done.
    param([string]$AppName, [string]$FilePath, [string[]]$Arguments)

    # Installers get an empty input stream instead of the console's keyboard input,
    # so nothing they launch can sit waiting for Enter. Output still shows on screen.
    $proc  = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -PassThru `
                           -RedirectStandardInput $EmptyInput
    $null  = $proc.Handle   # keeps the handle open so ExitCode is readable afterward
    $start = Get-Date

    while (-not $proc.HasExited) {
        $elapsed = (Get-Date) - $start
        $clock   = '{0}:{1:00}' -f [int][math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds
        Write-Progress -Id 2 -ParentId 1 -Activity "Installing $AppName" `
            -Status "Working... $clock elapsed" `
            -PercentComplete ([int]($elapsed.TotalSeconds * 4) % 100)
        Start-Sleep -Milliseconds 500
    }

    $proc.WaitForExit()
    Write-Progress -Id 2 -ParentId 1 -Activity "Installing $AppName" -Completed
    return $proc.ExitCode
}

# ---- Direct Microsoft installers (Office, Teams) ---------------------------
function Get-MicrosoftDownload {
    # Downloads a file and returns its path, but only if it has a valid digital
    # signature from Microsoft Corporation. Anything else is deleted and refused.
    param([string]$Url, [string]$FileName)

    New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null
    $path = Join-Path $DownloadDir $FileName
    Write-Log "  Downloading $FileName from Microsoft..."

    $ProgressPreference = 'SilentlyContinue'   # Windows PowerShell's download bar slows downloads badly
    Invoke-WebRequest -Uri $Url -OutFile $path -UseBasicParsing
    $ProgressPreference = 'Continue'

    $sig = Get-AuthenticodeSignature -FilePath $path
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        Remove-Item $path -Force -ErrorAction SilentlyContinue
        throw "$FileName is not validly signed by Microsoft (signature: $($sig.Status)). Not running it."
    }
    Write-Log '  Signature verified: Microsoft Corporation.' 'DarkGray'
    return $path
}

function Install-Office {
    param([hashtable]$App)
    $setup  = Get-MicrosoftDownload $OfficeSetupUrl 'office-setup.exe'
    $config = Join-Path $DownloadDir 'office-config.xml'
    Set-Content -Path $config -Value $OfficeConfig -Encoding UTF8
    Write-Log '  Office downloads about 3 GB while it installs. This usually takes 10-20 minutes.'
    return Invoke-WithProgress $App.Name $setup @('/configure', "`"$config`"")
}

function Install-Teams {
    param([hashtable]$App)
    $bootstrapper = Get-MicrosoftDownload $TeamsBootstrapperUrl 'teamsbootstrapper.exe'
    # -p sets Teams up for every user on the PC, including people who sign in later.
    return Invoke-WithProgress $App.Name $bootstrapper @('-p')
}

# ---- Check WinGet ----------------------------------------------------------
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Log 'WinGet was not found. Install or update "App Installer" from the Microsoft Store, then run this again.' 'Red'
    exit 1
}
$WingetExe = (Get-Command winget).Source

Disable-QuickEdit
$EmptyInput = Join-Path $LogDir 'empty-input.txt'
Set-Content -Path $EmptyInput -Value $null
# Older Windows PowerShell builds don't enable TLS 1.2 by default; Microsoft's download servers require it.
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

Write-Log "Starting new PC setup on $env:COMPUTERNAME" 'Cyan'
if ($CheckOnly) { Write-Log 'CHECK-ONLY mode: nothing will be installed.' 'Cyan' }
Write-Log 'Updating WinGet sources...'
winget source update | Out-Null

# WinGet exit code meaning "already installed / no newer version"
$AlreadyInstalled = -1978335189   # 0x8A15002B

$Total = $Apps.Count
$Step  = 0

$Results = foreach ($App in $Apps) {
    $Step++
    Write-Progress -Id 1 -Activity 'New PC Setup' `
        -Status "[$Step of $Total] $($App.Name)" `
        -CurrentOperation 'Checking whether it is already installed...' `
        -PercentComplete ((($Step - 1) / $Total) * 100)
    Write-Log "[$Step/$Total] Checking $($App.Name)..."

    $found = Find-InstalledApp $App
    if ($found) {
        Write-Log "  Already installed: $found. Skipping." 'DarkGray'
        [pscustomobject]@{ App = $App.Name; Result = 'Already installed'; Detail = $found }
        continue
    }

    $source = if ($App.Installer) { 'Microsoft download' } else { $App.Id }
    if ($CheckOnly) {
        Write-Log "  Not installed. Would install from $source." 'Yellow'
        [pscustomobject]@{ App = $App.Name; Result = 'Would install'; Detail = $source }
        continue
    }

    Write-Progress -Id 1 -Activity 'New PC Setup' `
        -Status "[$Step of $Total] $($App.Name)" `
        -CurrentOperation 'Downloading and installing (large apps like Office can take several minutes)...' `
        -PercentComplete ((($Step - 1) / $Total) * 100)
    Write-Log "  Installing $($App.Name)..." 'Yellow'
    $note = ''

    if ($App.Installer) {
        # Office and Teams: direct Microsoft installer.
        try {
            $code = switch ($App.Installer) {
                'Office' { Install-Office $App }
                'Teams'  { Install-Teams  $App }
                default  { throw "Unknown installer type '$($App.Installer)'." }
            }
        } catch {
            Write-Log "  $($App.Name) FAILED: $($_.Exception.Message)" 'Red'
            [pscustomobject]@{ App = $App.Name; Result = 'Failed'; Detail = $_.Exception.Message }
            continue
        }
        if ($code -ne 0) {
            $found = Find-InstalledApp $App
            if ($found) {
                Write-Log "  Installer returned exit $code, but $($App.Name) is now present." 'DarkYellow'
                $note = "installer returned $code"
                $code = 0
            }
        }
    } else {
        # Everything else: WinGet.
        $common = @('install', '--id', $App.Id, '--exact', '--silent',
                    '--accept-package-agreements', '--accept-source-agreements')

        # Prefer a machine-wide install; some packages only support per-user, so fall back.
        $code = Invoke-WithProgress $App.Name $WingetExe ($common + @('--scope', 'machine'))
        if ($code -ne 0 -and $code -ne $AlreadyInstalled) {
            # Some installers report an error even though they finished. Check before
            # retrying so we never put a second copy on the machine.
            $found = Find-InstalledApp $App
            if ($found) {
                Write-Log "  Installer returned exit $code, but $($App.Name) is now present. Not retrying." 'DarkYellow'
                $note = "installer returned $code"
                $code = 0
            } else {
                Write-Log "  Machine-wide install failed (exit $code), retrying with default scope..." 'DarkYellow'
                $code = Invoke-WithProgress $App.Name $WingetExe $common
            }
        }
    }

    if ($code -eq 0 -or $code -eq $AlreadyInstalled) {
        Write-Log "  $($App.Name) installed." 'Green'
        [pscustomobject]@{ App = $App.Name; Result = 'Installed'; Detail = $note }
    } else {
        Write-Log "  $($App.Name) FAILED (exit code $code)." 'Red'
        [pscustomobject]@{ App = $App.Name; Result = 'Failed'; Detail = "exit code $code" }
    }
}

Write-Progress -Id 1 -Activity 'New PC Setup' -Status 'Done' -PercentComplete 100
Start-Sleep -Milliseconds 500
Write-Progress -Id 1 -Activity 'New PC Setup' -Completed

# Clean up downloaded installers
Remove-Item $DownloadDir -Recurse -Force -ErrorAction SilentlyContinue

# ---- Summary ---------------------------------------------------------------
Write-Log '----------------------------------------' 'Cyan'
Write-Log 'Summary:' 'Cyan'
$Results | ForEach-Object { Write-Log ("  {0,-32} {1,-18} {2}" -f $_.App, $_.Result, $_.Detail) }
Write-Log "Log saved to $LogFile" 'Cyan'

if ($Results.Result -contains 'Failed') { exit 1 } else { exit 0 }
