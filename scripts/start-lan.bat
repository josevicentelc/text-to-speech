@echo off
setlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1" -BindHost 0.0.0.0 %*
exit /b %ERRORLEVEL%
