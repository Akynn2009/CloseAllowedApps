@echo off
set "APP=%~dp0CloseAllowedApps.exe"
if exist "%APP%" (
	powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Update-Required.ps1" -ApplicationPath "%APP%"
	if errorlevel 1 exit /b 1
	start "Close configured apps" "%APP%"
	exit /b 0
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Close-AllowedApps.ps1"
