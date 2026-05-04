$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$pidFile = Join-Path $root "server.pid"

if (-not (Test-Path $pidFile)) {
    Write-Host "No hay server.pid; nada que detener."
    exit 0
}

$serverPid = [int](Get-Content $pidFile -Raw)
$process = Get-Process -Id $serverPid -ErrorAction SilentlyContinue
if ($process) {
    Stop-Process -Id $serverPid
    Write-Host "Servicio detenido."
} else {
    Write-Host "El proceso indicado ya no existe."
}

Remove-Item $pidFile -Force

