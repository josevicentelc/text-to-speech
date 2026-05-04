#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="$ROOT/.venv/bin/python"
PID_FILE="$ROOT/server.pid"
OUT_LOG="$ROOT/server.out.log"
ERR_LOG="$ROOT/server.err.log"
BIND_HOST="${SPEECH_HOST:-127.0.0.1}"
PORT="${SPEECH_PORT:-8000}"

if [ ! -x "$PYTHON" ]; then
  echo "No se encontro Python en .venv. Ejecuta primero: ./scripts/install.sh" >&2
  exit 1
fi

if [ -f "$PID_FILE" ]; then
  PID="$(cat "$PID_FILE")"
  if kill -0 "$PID" >/dev/null 2>&1; then
    echo "El servicio ya parece estar corriendo con PID $PID"
    exit 0
  fi

  rm -f "$PID_FILE"
fi

cd "$ROOT"
nohup "$PYTHON" -m uvicorn app.main:app --host "$BIND_HOST" --port "$PORT" >"$OUT_LOG" 2>"$ERR_LOG" &
PID="$!"
echo "$PID" >"$PID_FILE"

sleep 2
if ! kill -0 "$PID" >/dev/null 2>&1; then
  rm -f "$PID_FILE"
  echo "El servicio no pudo arrancar. Revisa server.out.log y server.err.log." >&2
  exit 1
fi

echo "Servicio iniciado en http://$BIND_HOST:$PORT con PID $PID"
if [ "$BIND_HOST" = "0.0.0.0" ]; then
  echo "Desde otros equipos de la red usa la IP de este equipo, por ejemplo: http://192.168.10.205:$PORT"
fi
