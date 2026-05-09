$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$pidFile = Join-Path $root "server.pid"
$backendPidFile = Join-Path $root "server.backend.pid"

if (Test-Path $pidFile) {
    $serverPid = [int](Get-Content $pidFile -Raw)
    $process = Get-Process -Id $serverPid -ErrorAction SilentlyContinue
    if ($process) {
        Stop-Process -Id $serverPid
        Write-Host "Servicio detenido."
    } else {
        Write-Host "El proceso indicado ya no existe."
    }

    Remove-Item $pidFile -Force
} else {
    Write-Host "No hay server.pid."
}

if (Test-Path $backendPidFile) {
    $backendPid = [int](Get-Content $backendPidFile -Raw)
    $backendProcess = Get-Process -Id $backendPid -ErrorAction SilentlyContinue
    if ($backendProcess) {
        Stop-Process -Id $backendPid
        Write-Host "Backend Python detenido."
    }

    Remove-Item $backendPidFile -Force
}

$backendListeners = netstat -ano | Select-String -Pattern ":8765\s+.*LISTENING"
foreach ($listener in $backendListeners) {
    $columns = ($listener.Line -split "\s+") | Where-Object { $_ }
    $listenerPid = [int]$columns[-1]
    $listenerProcess = Get-Process -Id $listenerPid -ErrorAction SilentlyContinue
    if ($listenerProcess -and $listenerProcess.ProcessName -eq "python") {
        Stop-Process -Id $listenerPid
        Write-Host "Backend Python detenido en puerto 8765."
    }
}
