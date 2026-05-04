param(
    [switch]$SkipSystemDeps
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$venv = Join-Path $root ".venv"
$pythonExe = Join-Path $venv "Scripts\python.exe"

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-PythonCommand {
    if (Test-Command "py") {
        try {
            & py -3.11 -c "import sys; raise SystemExit(0 if sys.version_info[:2] == (3, 11) else 1)" | Out-Null
            return @("py", "-3.11")
        } catch {
        }

        try {
            & py -3.12 -c "import sys; raise SystemExit(0 if sys.version_info[:2] == (3, 12) else 1)" | Out-Null
            return @("py", "-3.12")
        } catch {
        }
    }

    if (Test-Command "python") {
        try {
            & python -c "import sys; raise SystemExit(0 if (3, 11) <= sys.version_info[:2] < (3, 13) else 1)" | Out-Null
            return @("python")
        } catch {
        }
    }

    throw "No se encontro Python 3.11 o 3.12. Instala Python desde https://www.python.org/downloads/ y vuelve a ejecutar este script."
}

function Install-EspeakNg {
    if (Test-Command "espeak-ng") {
        Write-Host "espeak-ng ya esta instalado."
        return
    }

    if ($SkipSystemDeps) {
        Write-Warning "espeak-ng no esta instalado. Se omitio por -SkipSystemDeps."
        return
    }

    if (Test-Command "winget") {
        Write-Host "Instalando espeak-ng con winget..."
        winget install --id eSpeak-NG.eSpeak-NG --exact --accept-package-agreements --accept-source-agreements
        if (Test-Command "espeak-ng") {
            return
        }
        Write-Warning "winget termino, pero espeak-ng no aparece en el PATH actual. Puede que tengas que abrir una terminal nueva."
        return
    }

    if (Test-Command "choco") {
        Write-Host "Instalando espeak-ng con Chocolatey..."
        choco install espeak-ng -y
        if (Test-Command "espeak-ng") {
            return
        }
        Write-Warning "Chocolatey termino, pero espeak-ng no aparece en el PATH actual. Puede que tengas que abrir una terminal nueva."
        return
    }

    Write-Warning "No se pudo instalar espeak-ng automaticamente. Instala espeak-ng y anadelo al PATH."
}

Set-Location $root
Install-EspeakNg

if (-not (Test-Path $venv)) {
    $pythonCommand = Get-PythonCommand
    Write-Host "Creando entorno virtual en .venv..."
    if ($pythonCommand.Length -eq 1) {
        & $pythonCommand[0] -m venv $venv
    } else {
        & $pythonCommand[0] $pythonCommand[1] -m venv $venv
    }
} else {
    Write-Host "Usando entorno virtual existente: .venv"
}

Write-Host "Actualizando pip..."
& $pythonExe -m pip install --upgrade pip

Write-Host "Instalando dependencias Python..."
& $pythonExe -m pip install -e .

Write-Host ""
Write-Host "Instalacion completada."
Write-Host "Arranca el servicio con:"
Write-Host "  powershell -ExecutionPolicy Bypass -File .\scripts\start.ps1"
