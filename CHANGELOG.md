# Changelog

## 1.0.0 (2026-10-16)

First public release.

- Installs Microsoft 365 Apps for business, Microsoft Teams, Adobe Acrobat, VLC, Google Chrome, Mozilla Firefox, and 7-Zip silently and machine-wide.
- Office and Teams install from Microsoft's official installers, verified by Microsoft's digital signature. Other apps install from the official WinGet repository.
- Skips apps that are already installed, however they were installed, so it's safe to run more than once.
- Never installs a second copy if an installer reports an error but actually finished.
- `-CheckOnly` mode shows what would be installed without changing anything.
- Progress bar with elapsed time during each install.
- Self-elevating launcher that works from any folder name.
- Summary at the end and a log of every run in `C:\ProgramData\NewPCSetup\`.
