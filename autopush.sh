#!/usr/bin/env bash
#
# Auto-commit & push for the WonderKids repositories.
#
# Checks each repo for changes and, if there are any, stages everything,
# commits with a timestamped message (authored as the owner's private account),
# and pushes to the configured remote. Repos with no changes are left alone.
#
# Usage:
#   ./scripts/autopush.sh                 # default commit message
#   ./scripts/autopush.sh "fix: wording"  # custom commit message
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MSG="${1:-chore: auto update $(date '+%Y-%m-%d %H:%M:%S')}"

# Commit identity (private account) applied per-command — never persisted,
# so your global git config stays untouched.
GIT_NAME="Yurii Luchyshyn"
GIT_EMAIL="jurilochishin@gmail.com"

# GitHub account that OWNS the remotes. Pushes must authenticate as this
# account (not whichever gh account happens to be "active" on the machine).
GH_USER="yuriiluchyshyn"

# Make the active GitHub account correct before any push, and route git auth
# through the gh credential helper for THIS account. Nothing is persisted into
# your global git config — the helper is passed per `git push` invocation.
PUSH_CRED=()
if command -v gh >/dev/null 2>&1; then
  if gh auth switch --hostname github.com --user "$GH_USER" >/dev/null 2>&1; then
    echo "🔑  GitHub-акаунт для пушу: $GH_USER"
  else
    echo "⚠️  Не вдалося переключити gh на $GH_USER (чи він залогінений?). Пушитиму поточним креденшелом."
  fi
  # Clear inherited helpers (e.g. osxkeychain), then use gh's for this account.
  PUSH_CRED=(-c "credential.helper=" -c "credential.helper=!gh auth git-credential")
else
  echo "⚠️  gh CLI не знайдено — пушитиму тим, що в git credential helper."
fi

# Repositories managed by this project.
REPOS=("$ROOT/app" "$ROOT/scripts")

pushed_any=0
for repo in "${REPOS[@]}"; do
  if [ ! -d "$repo/.git" ]; then
    echo "⏭️  Пропускаю (не git-репозиторій): $repo"
    continue
  fi

  cd "$repo"
  if [ -z "$(git status --porcelain)" ]; then
    echo "✓  Без змін: $repo"
    continue
  fi

  echo "→  Зміни знайдено в $repo — коміт і пуш..."
  git add -A
  git -c user.name="$GIT_NAME" -c user.email="$GIT_EMAIL" commit -m "$MSG"
  git "${PUSH_CRED[@]}" push
  echo "✅ Запушено: $repo"
  pushed_any=1
done

if [ "$pushed_any" -eq 0 ]; then
  echo "Нічого пушити — усі репозиторії актуальні."
fi
