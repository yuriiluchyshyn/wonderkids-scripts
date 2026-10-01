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
  git push
  echo "✅ Запушено: $repo"
  pushed_any=1
done

if [ "$pushed_any" -eq 0 ]; then
  echo "Нічого пушити — усі репозиторії актуальні."
fi
