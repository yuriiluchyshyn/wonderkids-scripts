#!/usr/bin/env bash
#
# Commit & push the WonderKids app/ repo → triggers a Vercel deployment.
#
# The app/ folder is its own git repo connected to Vercel, so pushing it
# redeploys both the frontend and the serverless API in app/api/*.
#
# Usage:
#   ./scripts/deploy-app.sh                      # default commit message
#   ./scripts/deploy-app.sh "feat: add login"    # custom commit message
#
# Set SKIP_BUILD=1 to skip the local production build check before pushing.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/app"
MSG="${1:-chore: deploy app $(date '+%Y-%m-%d %H:%M:%S')}"

# Commit identity (private account) applied per-command — never persisted,
# so your global git config stays untouched.
GIT_NAME="Yurii Luchyshyn"
GIT_EMAIL="jurilochishin@gmail.com"

if [ ! -d "$APP_DIR/.git" ]; then
  echo "❌  Не знайдено git-репозиторій у $APP_DIR"
  exit 1
fi

cd "$APP_DIR"

if [ -z "$(git status --porcelain)" ]; then
  echo "✓  Без змін у app/ — нічого деплоїти."
  exit 0
fi

# Catch build errors locally so a broken build never reaches Vercel.
if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "🔨  Перевіряю production-білд перед пушем..."
  npm run build
  echo "✅  Білд успішний."
fi

echo "→  Коміт і пуш змін у app/..."
git add -A
git -c user.name="$GIT_NAME" -c user.email="$GIT_EMAIL" commit -m "$MSG"
git push

echo ""
echo "🚀  Запушено. Vercel підхопить коміт і почне деплой."
echo "    Перевір статус: https://vercel.com/dashboard"
echo "    Після деплою:   curl https://wonderkids.yluch.app/api/health"
