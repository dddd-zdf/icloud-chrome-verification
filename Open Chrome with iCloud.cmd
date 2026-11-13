@echo off
start "" /min "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -MTA -WindowStyle Hidden -File "%~dp0Watch-ICloudChromeVerification.ps1" -Mode Launch
