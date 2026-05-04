#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="$ROOT/.venv"
PYTHON="$VENV/bin/python"
SKIP_SYSTEM_DEPS="${SKIP_SYSTEM_DEPS:-0}"

has_command() {
  command -v "$1" >/dev/null 2>&1
}

run_as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif has_command sudo; then
    sudo "$@"
  else
    echo "Necesito permisos de administrador para instalar dependencias de sistema." >&2
    echo "Instala sudo o ejecuta manualmente: $*" >&2
    return 1
  fi
}

install_espeak_ng() {
  if has_command espeak-ng; then
    echo "espeak-ng ya esta instalado."
    return
  fi

  if [ "$SKIP_SYSTEM_DEPS" = "1" ]; then
    echo "Aviso: espeak-ng no esta instalado. Se omitio por SKIP_SYSTEM_DEPS=1." >&2
    return
  fi

  if has_command apt-get; then
    run_as_root apt-get update
    run_as_root apt-get install -y espeak-ng
  elif has_command dnf; then
    run_as_root dnf install -y espeak-ng
  elif has_command yum; then
    run_as_root yum install -y espeak-ng
  elif has_command pacman; then
    run_as_root pacman -Sy --needed --noconfirm espeak-ng
  elif has_command zypper; then
    run_as_root zypper --non-interactive install espeak-ng
  elif has_command apk; then
    run_as_root apk add espeak-ng
  else
    echo "No se pudo detectar un gestor de paquetes compatible." >&2
    echo "Instala espeak-ng manualmente y vuelve a ejecutar este script." >&2
  fi
}

ensure_venv_module() {
  local python_cmd="$1"

  if "$python_cmd" -m venv --help >/dev/null 2>&1; then
    return
  fi

  echo "El modulo venv de Python no esta disponible. Intentando instalarlo..."

  if has_command apt-get; then
    run_as_root apt-get update
    if [ "$python_cmd" = "python3.11" ] || [ "$python_cmd" = "python3.12" ]; then
      run_as_root apt-get install -y "${python_cmd}-venv" || run_as_root apt-get install -y python3-venv
    else
      run_as_root apt-get install -y python3-venv
    fi
  elif has_command dnf; then
    run_as_root dnf install -y python3
  elif has_command yum; then
    run_as_root yum install -y python3
  elif has_command zypper; then
    run_as_root zypper --non-interactive install python3
  elif has_command apk; then
    run_as_root apk add py3-pip python3
  else
    echo "No se pudo instalar el modulo venv automaticamente." >&2
    echo "Instala el paquete venv de Python para tu distribucion y vuelve a ejecutar este script." >&2
  fi

  "$python_cmd" -m venv --help >/dev/null 2>&1 || {
    echo "El modulo venv sigue sin estar disponible para $python_cmd." >&2
    exit 1
  }
}

find_python() {
  for candidate in python3.12 python3.11 python3; do
    if has_command "$candidate" && "$candidate" - <<'PY'
import sys
raise SystemExit(0 if (3, 11) <= sys.version_info[:2] < (3, 13) else 1)
PY
    then
      echo "$candidate"
      return
    fi
  done

  echo "No se encontro Python 3.11 o 3.12." >&2
  exit 1
}

cd "$ROOT"
install_espeak_ng

if [ ! -d "$VENV" ]; then
  PYTHON_CMD="$(find_python)"
  ensure_venv_module "$PYTHON_CMD"
  echo "Creando entorno virtual en .venv..."
  "$PYTHON_CMD" -m venv "$VENV"
else
  echo "Usando entorno virtual existente: .venv"
fi

echo "Actualizando pip..."
"$PYTHON" -m pip install --upgrade pip

echo "Instalando dependencias Python..."
"$PYTHON" -m pip install -e .

echo
echo "Instalacion completada."
echo "Arranca el servicio con:"
echo "  ./scripts/start.sh"
