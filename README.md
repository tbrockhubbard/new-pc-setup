# New PC Setup

A double-click setup tool that installs a standard business app stack on a new Windows PC, using **WinGet** and Microsoft's official installers.

I built this while working as a technician at an MSP. Every new laptop meant the same 30+ minutes of downloading installers, clicking through prompts, and dodging bundled extras like McAfee. This script does it unattended, so the tech can move on to the next job while the machine sets itself up.

## What it installs

| App | Source |
|---|---|
| Microsoft 365 Apps for business (64-bit, including classic Outlook) | Microsoft download |
| Microsoft Teams (work or school), set up for all users | Microsoft download |
| Adobe Acrobat | WinGet `Adobe.Acrobat.Reader.64-bit` |
| VLC media player | WinGet `VideoLAN.VLC` |
| Google Chrome | WinGet `Google.Chrome` |
| Mozilla Firefox | WinGet `Mozilla.Firefox` |
| 7-Zip | WinGet `7zip.7zip` |

Everything comes from Microsoft or the official WinGet repository, so there's no bundled third-party software. Adobe's 64-bit installer is Adobe's unified installer: it runs as Reader and unlocks Acrobat Pro features when a licensed user signs in.

### Why Office and Teams skip WinGet

- **Office:** WinGet's `Microsoft.Office` package always installs the Enterprise edition, and it often fails with *"Installer hash does not match"* (exit code `-1978335215`). Microsoft updates the setup file at the same download link, which leaves WinGet's recorded hash out of date until the package is updated.
- **Teams:** WinGet's `Microsoft.Teams` package installs Teams only for the user running it. Microsoft's Teams bootstrapper (`teamsbootstrapper.exe -p`) sets it up for every user on the PC, including people who sign in later.

Both are downloaded straight from Microsoft. The script checks that each file has a valid digital signature from Microsoft Corporation and refuses to run it otherwise. Downloads are deleted when the run finishes.

Expect Office to take 10-20 minutes; it downloads about 3 GB as it installs.

### Changing the Office edition or apps

The Office settings are in the `$OfficeConfig` section near the top of `install-new-pc.ps1`. By default it installs **Microsoft 365 Apps for business**, 64-bit, Current Channel, in the same language as Windows, without Skype for Business, the old OneDrive for Business client, Teams (installed separately), or the "new Outlook".

To install **Microsoft 365 Apps for enterprise** (E3/E5 licenses) instead, change `O365BusinessRetail` to `O365ProPlusRetail`. For other options, Microsoft's [Office Customization Tool](https://config.office.com) builds this file for you.

## How to use it

**[Download the latest version](../../releases/latest)** (`new-pc-setup.zip` under Assets).

1. Copy both files (`Run-Setup.bat` and `install-new-pc.ps1`) to the new PC, in the same folder (a USB stick works). If you downloaded the zip, extract it first; don't run the launcher from inside the zip.
2. Double-click **`Run-Setup.bat`** and approve the UAC prompt.
3. Wait. When it finishes, you'll see a summary of what was installed, what was skipped, and anything that failed.

A log of every run is saved to `C:\ProgramData\NewPCSetup\`.

### Check-only mode

To see what the script would do without installing anything, run it from an elevated PowerShell window with `-CheckOnly`:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-new-pc.ps1 -CheckOnly
```

The summary shows each app as **Already installed** (with where it was found) or **Would install**.

## Features

- **Self-elevating launcher.** `Run-Setup.bat` requests admin rights and bypasses execution policy for that run only, so there's no need to change system settings.
- **Silent, machine-wide installs.** Falls back to the default scope if a package doesn't support machine-wide installs.
- **Skips what's already installed**, however it got there, so it's safe to run more than once. See [How "already installed" is detected](#how-already-installed-is-detected).
- **Never double-installs.** If an installer reports an error but the app is actually present afterward, the script logs it and doesn't retry.
- **Summary and log file** for documenting the job in the ticket.
- **Easy to customize.** Edit the `$Apps` list at the top of the script to add or remove apps for a specific client.

## Customizing for a client

Find an app's ID:

```powershell
winget search "app name"
```

Then add it to the `$Apps` list in `install-new-pc.ps1`:

```powershell
@{ Name  = 'Zoom'
   Id    = 'Zoom.Zoom'
   Match = '^Zoom Workplace' }
```

| Field | Required | What it does |
|---|---|---|
| `Name` | Yes | Friendly name shown on screen and in the log |
| `Id` | Yes | WinGet package ID to install |
| `Match` | Recommended | Regex matched against the app's name in **Settings > Apps > Installed apps** |
| `AltIds` | No | Other WinGet IDs that also mean "already installed" |
| `Exclude` | No | Regex for installed-app names that look like a match but aren't |

To get the right `Match` text, install the app on a test machine and copy its name from Installed apps.

To skip an app for a client (for example Teams), delete or comment out its entry in `$Apps`.

## How "already installed" is detected

Each app is checked two ways before anything is installed. If either one finds it, the app is skipped.

1. **Installed apps list (registry).** Covers machine-wide installs, 32-bit installs, and per-user installs for every signed-in user. This catches apps installed from anywhere: a vendor download, an OEM image, or a previous tech.
2. **WinGet's installed list**, using WinGet's exit code rather than reading its text output, and including any `AltIds`.

Teams doesn't appear in the installed apps list, so it's checked a third way: whether the Teams app is already set up for all users on the PC.

The second check matters for Chrome. The `Google.Chrome` WinGet package is Google's enterprise MSI, but Chrome downloaded from google.com shows up in WinGet as `Google.Chrome.EXE`. Checking only `Google.Chrome` misses it and installs Chrome a second time.

Limitation: per-user installs are only visible for users who are signed in when the script runs.

## Requirements

- Windows 10 or 11
- WinGet (included with the **App Installer** package from the Microsoft Store; preinstalled on current Windows builds)
- Administrator rights and an internet connection

## How it was built

I wrote this with help from Claude.ai, then tested and adjusted it on real client machines. Some packages needed different flags or scopes to install cleanly. AI got the first draft written fast; making it reliable was hands-on troubleshooting.

## License

MIT. See [LICENSE](LICENSE).
