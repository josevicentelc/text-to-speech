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

function Invoke-Checked {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$ErrorMessage
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw $ErrorMessage
    }
}

function Test-PythonVersion {
    param([string[]]$Command)

    $pythonArgs = @()
    if ($Command.Length -gt 1) {
        $pythonArgs = $Command[1..($Command.Length - 1)]
    }

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Command[0] @pythonArgs -c "import sys; raise SystemExit(0 if (3, 11) <= sys.version_info[:2] < (3, 13) else 1)" *> $null
        return $LASTEXITCODE -eq 0
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

function Update-PathFromEnvironment {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = @($machinePath, $userPath) -join ";"
}

function Find-PythonCommand {
    if (Test-Command "py") {
        if (Test-PythonVersion @("py", "-3.11")) {
            return @("py", "-3.11")
        }

        if (Test-PythonVersion @("py", "-3.12")) {
            return @("py", "-3.12")
        }
    }

    if (Test-Command "python") {
        if (Test-PythonVersion @("python")) {
            return @("python")
        }
    }

    $knownPythonPaths = @(
        (Join-Path $env:LocalAppData "Programs\Python\Python312\python.exe"),
        (Join-Path $env:LocalAppData "Programs\Python\Python311\python.exe"),
        (Join-Path $env:ProgramFiles "Python312\python.exe"),
        (Join-Path $env:ProgramFiles "Python311\python.exe")
    )

    foreach ($knownPythonPath in $knownPythonPaths) {
        if ((Test-Path $knownPythonPath) -and (Test-PythonVersion @($knownPythonPath))) {
            return @($knownPythonPath)
        }
    }

    return $null
}

function Install-Python {
    if (Find-PythonCommand) {
        Write-Host "Python 3.11/3.12 ya esta instalado."
        return
    }

    if ($SkipSystemDeps) {
        Write-Warning "Python 3.11/3.12 no esta instalado. Se omitio por -SkipSystemDeps."
        return
    }

    if (Test-Command "winget") {
        Write-Host "Instalando Python 3.12 con winget..."
        winget install --id Python.Python.3.12 --exact --scope user --accept-package-agreements --accept-source-agreements
        Update-PathFromEnvironment
        if (Find-PythonCommand) {
            return
        }

        Write-Warning "winget termino, pero Python 3.12 no aparece en el PATH actual. Puede que tengas que abrir una terminal nueva."
        return
    }

    if (Test-Command "choco") {
        Write-Host "Instalando Python 3.12 con Chocolatey..."
        choco install python312 -y
        Update-PathFromEnvironment
        if (Find-PythonCommand) {
            return
        }

        Write-Warning "Chocolatey termino, pero Python 3.12 no aparece en el PATH actual. Puede que tengas que abrir una terminal nueva."
        return
    }

    Write-Warning "No se pudo instalar Python automaticamente porque no se encontro winget ni Chocolatey."
}

function Get-PythonCommand {
    $pythonCommand = Find-PythonCommand
    if ($pythonCommand) {
        return $pythonCommand
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
if (-not (Test-Path $pythonExe)) {
    Install-Python
} else {
    Write-Host "Usando Python del entorno virtual existente: .venv"
}
Install-EspeakNg

if (-not (Test-Path $venv)) {
    $pythonCommand = Get-PythonCommand
    Write-Host "Creando entorno virtual en .venv..."
    if ($pythonCommand.Length -eq 1) {
        Invoke-Checked $pythonCommand[0] @("-m", "venv", $venv) "No se pudo crear el entorno virtual en .venv."
    } else {
        Invoke-Checked $pythonCommand[0] @($pythonCommand[1], "-m", "venv", $venv) "No se pudo crear el entorno virtual en .venv."
    }

    if (-not (Test-Path $pythonExe)) {
        throw "No se pudo crear el entorno virtual en .venv."
    }
} else {
    Write-Host "Usando entorno virtual existente: .venv"
}

Write-Host "Actualizando pip..."
Invoke-Checked $pythonExe @("-m", "pip", "install", "--upgrade", "pip") "No se pudo actualizar pip."

Write-Host "Instalando dependencias Python..."
Invoke-Checked $pythonExe @("-m", "pip", "install", "-e", ".") "No se pudieron instalar las dependencias Python."

Write-Host ""
Write-Host "Instalacion completada."
Write-Host "Arranca el servicio con:"
Write-Host "  powershell -ExecutionPolicy Bypass -File .\scripts\start.ps1"
Write-Host "  scripts\start.bat"
