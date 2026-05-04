#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$ROOT/server.pid"

if [ ! -f "$PID_FILE" ]; then
  echo "No hay server.pid; nada que detener."
  exit 0
fi

PID="$(cat "$PID_FILE")"
if kill -0 "$PID" >/dev/null 2>&1; then
  kill "$PID"
  echo "Servicio detenido."
else
  echo "El proceso indicado ya no existe."
fi

rm -f "$PID_FILE"

