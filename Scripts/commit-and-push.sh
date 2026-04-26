#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 \"commit message\""
    exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

remote_name="${GIT_REMOTE_NAME:-origin}"
remote_url="${GIT_REMOTE_URL:-https://github.com/xModern54/Task-Manager-MacOS.git}"
push_delay_seconds="${GIT_PUSH_DELAY_SECONDS:-1}"
commit_message="$*"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not inside a git repository: $repo_root"
    exit 1
fi

if ! git remote get-url "$remote_name" >/dev/null 2>&1; then
    git remote add "$remote_name" "$remote_url"
fi

git add -A

if git diff --cached --quiet; then
    echo "No staged changes to commit."
else
    git commit -m "$commit_message"
fi

sleep "$push_delay_seconds"

branch="$(git branch --show-current)"
if [ -z "$branch" ]; then
    echo "Cannot push from a detached HEAD."
    exit 1
fi

if git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
    git push
else
    git push -u "$remote_name" "$branch"
fi
