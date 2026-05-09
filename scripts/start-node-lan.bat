@echo off
setlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-node.ps1" -BindHost 0.0.0.0 %*
exit /b %ERRORLEVEL%
