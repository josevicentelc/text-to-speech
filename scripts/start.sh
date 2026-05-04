#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UVICORN="$ROOT/.venv/bin/uvicorn"
PID_FILE="$ROOT/server.pid"
OUT_LOG="$ROOT/server.out.log"
ERR_LOG="$ROOT/server.err.log"

if [ ! -x "$UVICORN" ]; then
  echo "No se encontro Uvicorn en .venv. Ejecuta primero: ./scripts/install.sh" >&2
  exit 1
fi

if [ -f "$PID_FILE" ]; then
  PID="$(cat "$PID_FILE")"
  if kill -0 "$PID" >/dev/null 2>&1; then
    echo "El servicio ya parece estar corriendo con PID $PID"
    exit 0
  fi
fi

cd "$ROOT"
nohup "$UVICORN" app.main:app --host 127.0.0.1 --port 8000 >"$OUT_LOG" 2>"$ERR_LOG" &
echo "$!" >"$PID_FILE"
echo "Servicio iniciado en http://127.0.0.1:8000 con PID $!"

