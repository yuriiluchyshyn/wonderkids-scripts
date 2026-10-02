#!/usr/bin/env bash
#
# Steps 1–2 of the subdomain guide, automated via the Vercel CLI.
# Adds parents.<domain> and play.<domain> to THIS project and prints the DNS
# records you then create at your registrar.
#
# Prerequisites (one-time, interactive — must be done by you):
#   1. Log in:      vercel login          (or: export VERCEL_TOKEN=xxxxxxxx)
#   2. Then run:    ./scripts/setup-vercel-domains.sh <root-domain>
#                   e.g. ./scripts/setup-vercel-domains.sh wonderkids.app
#
set -euo pipefail

DOMAIN="${1:-}"
if [ -z "$DOMAIN" ]; then
  echo "✋  Вкажи кореневий домен, напр.:"
  echo "    ./scripts/setup-vercel-domains.sh wonderkids.app"
  exit 1
fi

# Pass a token through if the environment provides one (CI / non-interactive).
TOKEN_ARG=()
if [ -n "${VERCEL_TOKEN:-}" ]; then TOKEN_ARG=(--token "$VERCEL_TOKEN"); fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/../app" && pwd)"
cd "$APP_DIR"   # the Vercel project lives in app/ (where vercel.json is)

echo "👤  Перевіряю вхід у Vercel…"
# `</dev/null` so that, if credentials are missing, the CLI gets EOF and fails
# fast instead of hanging on an interactive login prompt.
if ! WHOAMI="$(vercel whoami "${TOKEN_ARG[@]}" </dev/null 2>/dev/null)"; then
  echo "✋  Ти не залогінений. Спочатку виконай:  vercel login"
  echo "    (або:  export VERCEL_TOKEN=... )"
  exit 1
fi
echo "✅  Вхід ок: ${WHOAMI}"

echo ""
echo "🔗  Прив'язую каталог app/ до Vercel-проєкту (інтерактивно першого разу)…"
vercel link "${TOKEN_ARG[@]}"

# Read the linked project id so we attach domains to THIS project explicitly
# (CLI signature: `vercel domains add <domain> [project]`).
PROJECT=""
if [ -f .vercel/project.json ]; then
  PROJECT="$(node -p "require('./.vercel/project.json').projectId" 2>/dev/null || true)"
fi

echo ""
echo "🌐  Додаю піддомени до проєкту…"
for sub in parents play; do
  echo "   • ${sub}.${DOMAIN}"
  # Confirm any prompt with 'y'. The trailing project arg is omitted when the
  # link didn't expose an id (then the linked directory context is used).
  vercel domains add "${sub}.${DOMAIN}" ${PROJECT:+"$PROJECT"} "${TOKEN_ARG[@]}" || \
    echo "     ⚠️  Якщо домен уже доданий чи треба підтвердження — доглянь вивід вище."
done

echo ""
echo "✅  Кроки 1–2 завершено. Тепер DNS у реєстратора (Крок 2):"
echo "    CNAME  parents  →  cname.vercel-dns.com"
echo "    CNAME  play     →  cname.vercel-dns.com"
echo ""
echo "ℹ️   Точні значення DNS Vercel також показує у Project → Settings → Domains."
echo "    Перевірити стан:  vercel domains inspect ${DOMAIN}"
