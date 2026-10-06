#!/usr/bin/env bash
#
# Launch the ДивоСвіт / WonderKids dev server.
#
# One process: Vite serves the frontend AND the API. The serverless functions in
# app/api/* are mounted by the dev-api.ts Vite plugin, so local dev runs the same
# API code that is deployed to Vercel. Vite binds to all network interfaces
# (--host) so you can open the app from a phone or tablet on the same Wi-Fi —
# the primary target devices for this project.
#
# Usage:
#   ./scripts/dev.sh            # http://localhost:4321 (frontend + /api)
#   ./scripts/dev.sh 4500       # custom port
#
# The API uses DATABASE_URL / JWT_SECRET from app/.env.local (currently the
# production Neon database). Without DATABASE_URL it falls back to the local
# Docker Postgres (`docker compose up -d db`) — see app/.env.example.
#
set -euo pipefail

PORT="${1:-4321}"

# Resolve directories relative to this script, so it works from anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/../app" && pwd)"

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
npm run dev -- --port "$PORT" --host
