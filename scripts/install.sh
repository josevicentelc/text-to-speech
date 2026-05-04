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

install_packages() {
  if [ "$SKIP_SYSTEM_DEPS" = "1" ]; then
    return 1
  fi

  if has_command apt-get; then
    run_as_root apt-get update
    run_as_root apt-get install -y "$@"
  elif has_command dnf; then
    run_as_root dnf install -y "$@"
  elif has_command yum; then
    run_as_root yum install -y "$@"
  elif has_command pacman; then
    run_as_root pacman -Sy --needed --noconfirm "$@"
  elif has_command zypper; then
    run_as_root zypper --non-interactive install "$@"
  elif has_command apk; then
    run_as_root apk add "$@"
  else
    return 1
  fi
}

python_is_supported() {
  "$1" - <<'PY'
import sys
raise SystemExit(0 if (3, 11) <= sys.version_info[:2] < (3, 13) else 1)
PY
}

find_python() {
  for candidate in python3.12 python3.11 python3; do
    if has_command "$candidate" && python_is_supported "$candidate"; then
      echo "$candidate"
      return
    fi
  done

  return 1
}

install_python() {
  if find_python >/dev/null 2>&1; then
    echo "Python 3.11/3.12 ya esta instalado."
    return
  fi

  if [ "$SKIP_SYSTEM_DEPS" = "1" ]; then
    echo "Aviso: Python 3.11/3.12 no esta instalado. Se omitio por SKIP_SYSTEM_DEPS=1." >&2
    return
  fi

  if has_command apt-get; then
    run_as_root apt-get update
    run_as_root apt-get install -y python3.12 python3.12-venv python3.12-dev ||
      run_as_root apt-get install -y python3.11 python3.11-venv python3.11-dev ||
      run_as_root apt-get install -y python3 python3-venv python3-dev
  elif has_command dnf; then
    run_as_root dnf install -y python3.12 python3.12-devel ||
      run_as_root dnf install -y python3.11 python3.11-devel ||
      run_as_root dnf install -y python3 python3-devel
  elif has_command yum; then
    run_as_root yum install -y python3.12 python3.12-devel ||
      run_as_root yum install -y python3.11 python3.11-devel ||
      run_as_root yum install -y python3 python3-devel
  elif has_command pacman; then
    run_as_root pacman -Sy --needed --noconfirm python
  elif has_command zypper; then
    run_as_root zypper --non-interactive install python312 python312-devel ||
      run_as_root zypper --non-interactive install python311 python311-devel ||
      run_as_root zypper --non-interactive install python3 python3-devel
  elif has_command apk; then
    run_as_root apk add python3 python3-dev py3-pip
  else
    echo "No se pudo detectar un gestor de paquetes compatible." >&2
    echo "Instala Python 3.11 o 3.12 manualmente y vuelve a ejecutar este script." >&2
    return
  fi

  if ! find_python >/dev/null 2>&1; then
    echo "No se encontro Python 3.11 o 3.12 despues de intentar instalarlo." >&2
    exit 1
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

  if ! install_packages espeak-ng; then
    echo "No se pudo detectar un gestor de paquetes compatible." >&2
    echo "Instala espeak-ng manualmente y vuelve a ejecutar este script." >&2
  fi
}

install_runtime_libs() {
  if [ "$SKIP_SYSTEM_DEPS" = "1" ]; then
    return
  fi

  if has_command apt-get; then
    run_as_root apt-get update
    run_as_root apt-get install -y ca-certificates libgomp1
  elif has_command dnf; then
    run_as_root dnf install -y ca-certificates libgomp
  elif has_command yum; then
    run_as_root yum install -y ca-certificates libgomp
  elif has_command pacman; then
    run_as_root pacman -Sy --needed --noconfirm ca-certificates gcc-libs
  elif has_command zypper; then
    run_as_root zypper --non-interactive install ca-certificates libgomp1
  elif has_command apk; then
    run_as_root apk add ca-certificates libgomp
  else
    echo "Aviso: no se pudo detectar un gestor de paquetes para instalar librerias de runtime." >&2
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

cd "$ROOT"
if [ ! -x "$PYTHON" ]; then
  install_python
else
  echo "Usando Python del entorno virtual existente: .venv"
fi
install_espeak_ng
install_runtime_libs

if [ ! -d "$VENV" ]; then
  PYTHON_CMD="$(find_python)" || {
    echo "No se encontro Python 3.11 o 3.12." >&2
    exit 1
  }
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
