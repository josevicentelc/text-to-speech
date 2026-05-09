param(
    [string]$BindHost = $env:SPEECH_HOST,
    [int]$Port = $(if ($env:SPEECH_PORT) { [int]$env:SPEECH_PORT } else { 8000 }),
    [int]$BackendPort = $(if ($env:SPEECH_BACKEND_PORT) { [int]$env:SPEECH_BACKEND_PORT } else { 8765 })
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($BindHost)) {
    $BindHost = "127.0.0.1"
}

$root = Split-Path -Parent $PSScriptRoot
$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
$serverJs = Join-Path $root "server.js"
$pythonExe = Join-Path $root ".venv\Scripts\python.exe"
$pidFile = Join-Path $root "server.pid"
$backendPidFile = Join-Path $root "server.backend.pid"
$outLog = Join-Path $root "server.out.log"
$errLog = Join-Path $root "server.err.log"

if (-not $nodeCommand) {
    throw "No se encontro node.exe en PATH."
}

if (-not (Test-Path $serverJs)) {
    throw "No se encontro server.js."
}

if (-not (Test-Path $pythonExe)) {
    throw "No se encontro Python en .venv. Ejecuta primero: scripts\install.bat"
}

if (Test-Path $pidFile) {
    $existingPid = Get-Content $pidFile -Raw
    $existing = Get-Process -Id ([int]$existingPid) -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Error "El servicio ya parece estar corriendo con PID $existingPid. Ejecuta primero scripts\stop.bat y vuelve a arrancar."
        exit 1
    }

    Remove-Item $pidFile -Force
}

if (Test-Path $backendPidFile) {
    $existingBackendPid = Get-Content $backendPidFile -Raw
    $existingBackend = Get-Process -Id ([int]$existingBackendPid) -ErrorAction SilentlyContinue
    if ($existingBackend) {
        Write-Error "El backend Python ya parece estar corriendo con PID $existingBackendPid. Ejecuta primero scripts\stop.bat y vuelve a arrancar."
        exit 1
    }

    Remove-Item $backendPidFile -Force
}

$env:SPEECH_HOST = $BindHost
$env:SPEECH_PORT = [string]$Port
$env:SPEECH_BACKEND_PORT = [string]$BackendPort

$process = Start-Process `
    -FilePath $nodeCommand.Source `
    -ArgumentList "server.js" `
    -WorkingDirectory $root `
    -RedirectStandardOutput $outLog `
    -RedirectStandardError $errLog `
    -WindowStyle Hidden `
    -PassThru

$process.Id | Set-Content $pidFile

$healthUrl = "http://127.0.0.1:$Port/health"
$ready = $false
for ($attempt = 1; $attempt -le 45; $attempt++) {
    $running = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
    if (-not $running) {
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
        Write-Error "El servicio Node no pudo arrancar. Revisa server.out.log y server.err.log."
        exit 1
    }

    try {
        Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 1 | Out-Null
        $ready = $true
        break
    } catch {
        Start-Sleep -Seconds 1
    }
}

if (-not $ready) {
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    if (Test-Path $backendPidFile) {
        $backendPid = [int](Get-Content $backendPidFile -Raw)
        Stop-Process -Id $backendPid -ErrorAction SilentlyContinue
        Remove-Item $backendPidFile -Force -ErrorAction SilentlyContinue
    }
    Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
    Write-Error "El servicio Node arranco pero no respondio en $healthUrl tras 45 segundos. Revisa server.out.log y server.err.log."
    exit 1
}

Write-Host "Servicio iniciado con Node en http://$($BindHost):$Port con PID $($process.Id)"
Write-Host "Backend Python privado en http://127.0.0.1:$BackendPort"
if ($BindHost -eq "0.0.0.0") {
    $ipconfigOutput = ipconfig
    $lanAddresses = $ipconfigOutput |
        Select-String -Pattern "IPv4.*:\s*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)" |
        ForEach-Object { $_.Matches[0].Groups[1].Value } |
        Where-Object { $_ -and $_ -notlike "127.*" -and $_ -notlike "169.254.*" -and $_ -notlike "192.168.56.*" } |
        Sort-Object -Unique

    if ($lanAddresses.Count -gt 0) {
        Write-Host "Desde otros equipos de la red usa una de estas URLs:"
        $lanAddresses | ForEach-Object { Write-Host "  http://$($_):$Port" }
    }
}
