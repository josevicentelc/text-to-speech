$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$pythonExe = Join-Path $root ".venv\Scripts\python.exe"
$pidFile = Join-Path $root "server.pid"
$outLog = Join-Path $root "server.out.log"
$errLog = Join-Path $root "server.err.log"

if (-not (Test-Path $pythonExe)) {
    throw "No se encontro Python en .venv. Ejecuta primero: scripts\install.bat"
}

if (Test-Path $pidFile) {
    $existingPid = Get-Content $pidFile -Raw
    $existing = Get-Process -Id ([int]$existingPid) -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "El servicio ya parece estar corriendo con PID $existingPid"
        exit 0
    }

    Remove-Item $pidFile -Force
}

$process = Start-Process `
    -FilePath $pythonExe `
    -ArgumentList "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "8000" `
    -WorkingDirectory $root `
    -RedirectStandardOutput $outLog `
    -RedirectStandardError $errLog `
    -WindowStyle Hidden `
    -PassThru

$process.Id | Set-Content $pidFile

Start-Sleep -Seconds 2
$running = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
if (-not $running) {
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    Write-Error "El servicio no pudo arrancar. Revisa server.out.log y server.err.log."
    exit 1
}

Write-Host "Servicio iniciado en http://127.0.0.1:8000 con PID $($process.Id)"

