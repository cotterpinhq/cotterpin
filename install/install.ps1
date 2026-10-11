# Cotterpin on Windows runs inside WSL (Windows Subsystem for Linux).
#
#   irm https://cotterpin.io/install.ps1 | iex
#
# This script installs nothing itself. It says what is needed and, if you agree, starts the Windows installer for WSL,
# which needs an administrator and a restart.
$ErrorActionPreference = 'Stop'

Write-Host 'Cotterpin runs inside WSL on Windows, not in PowerShell.'
$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if ($wsl) {
    Write-Host 'WSL is available. Open Ubuntu (or run: wsl) and install Cotterpin there:'
    Write-Host '  curl -fsSL https://cotterpin.io/install.sh | sh'
    exit 0
}

Write-Host ''
Write-Host 'WSL is not installed. Cotterpin would like to start the Windows installer for it:'
Write-Host '  wsl --install   (installs Ubuntu; needs an administrator, then a restart)'
$answer = Read-Host 'Start it now? [y/N]'
if ($answer -match '^(y|yes)$') {
    Start-Process -FilePath 'wsl.exe' -ArgumentList '--install' -Verb RunAs -Wait
    Write-Host 'Restart Windows, open Ubuntu, then run:'
    Write-Host '  curl -fsSL https://cotterpin.io/install.sh | sh'
} else {
    Write-Host 'Nothing was changed. To install WSL yourself, run in an administrator PowerShell: wsl --install'
}
