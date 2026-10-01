#!/usr/bin/env bash
#
# Launch the ДивоСвіт / WonderKids dev stack: API backend + Vite frontend.
#
# Starts the Express API (port 3001 by default) in the background and the Vite
# dev server in the foreground. Vite proxies /api -> the backend, so login and
# saved state work out of the box. Vite binds to all network interfaces (--host)
# so you can open the app from a phone or tablet on the same Wi-Fi — the primary
# target devices for this project.
#
# Usage:
#   ./scripts/dev.sh            # frontend http://localhost:4321, API :3001
#   ./scripts/dev.sh 4500       # custom frontend port
#
# Env:
#   API_PORT=3001               # override the backend port (frontend proxy
#                               # follows automatically via VITE_API_TARGET)
#
set -euo pipefail

PORT="${1:-4321}"
API_PORT="${API_PORT:-3001}"

# Resolve directories relative to this script, so it works from anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/../app" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/../server" && pwd)"

# ---------------------------------------------------------------------------
# Backend (Express API)
# ---------------------------------------------------------------------------
if [ ! -f "$SERVER_DIR/.env" ]; then
  echo "⚠️   server/.env not found — copying from .env.example"
  echo "     Edit server/.env to point at your database before logging in."
  cp "$SERVER_DIR/.env.example" "$SERVER_DIR/.env"
fi

if [ ! -d "$SERVER_DIR/node_modules" ]; then
  echo "📦  server: node_modules not found — installing dependencies..."
  (cd "$SERVER_DIR" && npm install)
fi

echo ""
echo "🔌  API стартує на порту $API_PORT"
(cd "$SERVER_DIR" && PORT="$API_PORT" npm run dev) &
API_PID=$!

# Make sure the backend is torn down whenever this script exits (Ctrl-C, error…).
cleanup() {
  if kill -0 "$API_PID" 2>/dev/null; then
    echo ""
    echo "🧹  Зупиняю API (pid $API_PID)…"
    kill "$API_PID" 2>/dev/null || true
    wait "$API_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# Frontend (Vite)
# ---------------------------------------------------------------------------
cd "$APP_DIR"

if [ ! -d node_modules ]; then
  echo "📦  app: node_modules not found — installing dependencies..."
  npm install
fi

echo ""
echo "🦄  ДивоСвіт стартує на порту $PORT"
echo "    Локально:  http://localhost:$PORT"
echo "    На телефоні/планшеті: відкрий 'Network' URL нижче (та сама Wi-Fi)"
echo ""

# --host exposes the server on the LAN; Vite then prints the Network URL to
# open on a mobile device. Port is not strict, so it auto-increments if busy.
# Point the /api proxy at the backend port we started above.
VITE_API_TARGET="http://localhost:$API_PORT" npm run dev -- --port "$PORT" --host
