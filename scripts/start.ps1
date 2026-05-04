$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$uvicorn = Join-Path $root ".venv\Scripts\uvicorn.exe"
$pidFile = Join-Path $root "server.pid"
$outLog = Join-Path $root "server.out.log"
$errLog = Join-Path $root "server.err.log"

if (-not (Test-Path $uvicorn)) {
    throw "No se encontro Uvicorn en .venv. Ejecuta primero: python -m pip install -e ."
}

if (Test-Path $pidFile) {
    $existingPid = Get-Content $pidFile -Raw
    $existing = Get-Process -Id ([int]$existingPid) -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "El servicio ya parece estar corriendo con PID $existingPid"
        exit 0
    }
}

$process = Start-Process `
    -FilePath $uvicorn `
    -ArgumentList "app.main:app", "--host", "127.0.0.1", "--port", "8000" `
    -WorkingDirectory $root `
    -RedirectStandardOutput $outLog `
    -RedirectStandardError $errLog `
    -WindowStyle Hidden `
    -PassThru

$process.Id | Set-Content $pidFile
Write-Host "Servicio iniciado en http://127.0.0.1:8000 con PID $($process.Id)"

