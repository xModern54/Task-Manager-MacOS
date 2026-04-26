#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 \"commit message\""
    exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

app_dir="$repo_root/.build/debug/TaskMgmtMac.app"
executable="$repo_root/.build/debug/TaskMgmtMac"
helper_executable="$repo_root/.build/debug/TaskMgmtMacPrivilegedSensorHelper"
helper_plist_source="$repo_root/Resources/LaunchDaemons/com.xmodern.TaskMgmtMac.PrivilegedSensorHelper.plist"
plist="$app_dir/Contents/Info.plist"
helper_bundle_id="com.xmodern.TaskMgmtMac.PrivilegedSensorHelper"
remote_name="${GIT_REMOTE_NAME:-origin}"
remote_url="${GIT_REMOTE_URL:-https://github.com/xModern54/Task-Manager-MacOS.git}"
push_delay_seconds="${GIT_PUSH_DELAY_SECONDS:-1}"
commit_message="$*"
log_dir="${TMPDIR:-/tmp}/taskmgmtmac-finish-task"

mkdir -p "$log_dir"

run_quietly() {
    local label="$1"
    shift

    local log_file="$log_dir/${label// /-}.log"

    echo "==> $label"

    if "$@" >"$log_file" 2>&1; then
        return 0
    fi

    echo "Error while running: $label"
    echo "Log: $log_file"
    cat "$log_file"
    exit 1
}

codesign_identity() {
    if [ -n "${TASKMGMT_CODESIGN_IDENTITY:-}" ]; then
        printf '%s\n' "$TASKMGMT_CODESIGN_IDENTITY"
        return
    fi

    security find-identity -v -p codesigning 2>/dev/null \
        | awk -F '"' '/Apple Development|Developer ID Application/ { print $2; exit }'
}

echo "Finishing task: $commit_message"

run_quietly "swift build" swift build

echo "==> restart TaskMgmtMac"
pkill -x TaskMgmtMac 2>/dev/null || true
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Library/LaunchDaemons"
cp "$executable" "$app_dir/Contents/MacOS/TaskMgmtMac"
cp "$helper_executable" "$app_dir/Contents/MacOS/TaskMgmtMacPrivilegedSensorHelper"
cp "$helper_plist_source" "$app_dir/Contents/Library/LaunchDaemons/com.xmodern.TaskMgmtMac.PrivilegedSensorHelper.plist"

plutil -create xml1 "$plist" >/dev/null
/usr/libexec/PlistBuddy \
    -c "Add :CFBundleExecutable string TaskMgmtMac" \
    -c "Add :CFBundleIdentifier string com.xmodern.TaskMgmtMac" \
    -c "Add :CFBundleName string TaskMgmtMac" \
    -c "Add :CFBundlePackageType string APPL" \
    -c "Add :CFBundleVersion string 1" \
    -c "Add :CFBundleShortVersionString string 0.1" \
    -c "Add :LSMinimumSystemVersion string 14.0" \
    "$plist" >/dev/null

sign_identity="$(codesign_identity)"
if [ -z "$sign_identity" ]; then
    echo "Warning: no Apple Development/Developer ID signing identity found; using ad-hoc signing."
    echo "         The privileged helper will build, but macOS will block it until the app is signed with a Team ID."
    sign_identity="-"
fi

run_quietly "codesign helper" codesign --force --sign "$sign_identity" --identifier "$helper_bundle_id" "$app_dir/Contents/MacOS/TaskMgmtMacPrivilegedSensorHelper"
run_quietly "codesign app" codesign --force --sign "$sign_identity" --deep "$app_dir"

open "$app_dir"

echo "==> git sync"
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
    run_quietly "git commit" git commit -m "$commit_message"
fi

sleep "$push_delay_seconds"

branch="$(git branch --show-current)"
if [ -z "$branch" ]; then
    echo "Cannot push from a detached HEAD."
    exit 1
fi

if git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
    run_quietly "git push" git push
else
    run_quietly "git push" git push -u "$remote_name" "$branch"
fi

echo "Done."
