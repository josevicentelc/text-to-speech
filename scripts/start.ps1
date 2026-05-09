param(
    [string]$BindHost = $env:SPEECH_HOST,
    [int]$Port = $(if ($env:SPEECH_PORT) { [int]$env:SPEECH_PORT } else { 8000 })
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($BindHost)) {
    $BindHost = "127.0.0.1"
}

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
        Write-Error "El servicio ya parece estar corriendo con PID $existingPid. Ejecuta primero scripts\stop.bat y vuelve a arrancar."
        exit 1
    }

    Remove-Item $pidFile -Force
}

$process = Start-Process `
    -FilePath $pythonExe `
    -ArgumentList "-m", "uvicorn", "app.main:app", "--host", $BindHost, "--port", $Port `
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
        Write-Error "El servicio no pudo arrancar. Revisa server.out.log y server.err.log."
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
    Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
    Write-Error "El servicio arranco pero no respondio en $healthUrl tras 45 segundos. Revisa server.out.log y server.err.log."
    exit 1
}

$listeners = netstat -ano | Select-String -Pattern ":$Port\s+.*LISTENING"
if ($BindHost -eq "0.0.0.0" -and -not ($listeners -match "0\.0\.0\.0:$Port|\[::\]:$Port")) {
    Write-Warning "El servicio responde localmente, pero no aparece escuchando en 0.0.0.0:$Port. Salida netstat:"
    $listeners | ForEach-Object { Write-Warning $_.Line }
}

Write-Host "Servicio iniciado en http://$($BindHost):$Port con PID $($process.Id)"
if ($BindHost -eq "0.0.0.0") {
    $lanAddresses = @()
    try {
        $lanAddresses = Get-NetIPConfiguration |
            Where-Object { $_.IPv4DefaultGateway -and $_.IPv4Address } |
            ForEach-Object { $_.IPv4Address.IPAddress } |
            Where-Object { $_ -and $_ -notlike "127.*" } |
            Sort-Object -Unique
    } catch {
        $ipconfigOutput = ipconfig
        $lanAddresses = $ipconfigOutput |
            Select-String -Pattern "IPv4.*:\s*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)" |
            ForEach-Object { $_.Matches[0].Groups[1].Value } |
            Where-Object { $_ -and $_ -notlike "127.*" -and $_ -notlike "169.254.*" } |
            Sort-Object -Unique
    }

    if ($lanAddresses.Count -gt 0) {
        Write-Host "Desde otros equipos de la red usa una de estas URLs:"
        $lanAddresses | ForEach-Object { Write-Host "  http://$($_):$Port" }
    } else {
        Write-Host "Desde otros equipos de la red usa la IP LAN de este equipo, por ejemplo: http://192.168.1.50:$Port"
    }
    Write-Host "No uses http://0.0.0.0:$Port desde otro equipo; 0.0.0.0 solo indica que el servidor escucha en todas las interfaces."
}
