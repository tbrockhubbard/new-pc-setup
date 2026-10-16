@echo off
REM ============================================
REM Launcher for install-new-pc.ps1
REM Double-click this file to run the setup script.
REM It will auto-elevate (UAC prompt) and bypass execution policy
REM for this run only.
REM
REM Written to work from any folder name, including ones with spaces,
REM parentheses, or apostrophes, like "new-pc-setup (1)" from a repeat download.
REM ============================================

set "SELF=%~f0"
set "SCRIPT=%~dp0install-new-pc.ps1"

REM Make sure the script is next to this file (it won't be if this was run
REM from inside the zip without extracting it first).
if not exist "%SCRIPT%" goto :missing

REM Check for admin rights; if not elevated, relaunch elevated
net session >nul 2>&1
if %errorLevel% EQU 0 goto :elevated

echo Requesting administrator privileges...
REM The path is passed through an environment variable and wrapped in doubled
REM quotes so cmd.exe keeps it intact after elevation, whatever characters it has.
powershell -NoProfile -Command "$q = [char]34; Start-Process -FilePath cmd.exe -Verb RunAs -ArgumentList ('/c ' + $q + $q + $env:SELF + $q + $q)"
exit /b

:elevated
REM Now running elevated - launch the PowerShell script
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
echo.
pause
exit /b

:missing
echo.
echo Could not find install-new-pc.ps1 next to this file.
echo.
echo Extract the whole zip to a folder first, then run Run-Setup.bat from there.
echo Both files need to be in the same folder.
echo.
pause
exit /b 1
