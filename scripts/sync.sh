#!/usr/bin/env bash
# Sync Jarvis with GitHub.
#
#   bash scripts/sync.sh --pull                  get the latest notes (and code updates) before a request
#   bash scripts/sync.sh "type: summary"         commit every note change and push it
#   bash scripts/sync.sh --auto                  safety net run by the Stop hook; never blocks
#   bash scripts/sync.sh --code "type: summary"  commit and push changes to setup files
#
# Notes live in jarvis-vault/, their own private repository. Setup files live in
# the project folder, the code repository, which ignores jarvis-vault/.
#
# Every sync does the same steps, in this order:
#   1. commit anything uncommitted, so local work is safe before touching the remote
#   2. fetch
#   3. rebase local commits onto the remote, keeping history in one line
#   4. push; if the remote moved since the fetch, go back to step 2 (3 tries in all)
# Only one sync runs at a time per repository. Nothing is ever force pushed,
# reset, or discarded.

set -u

root="$(cd "$(dirname "$0")/.." && pwd)" || exit 1
target="$root/jarvis-vault"

mode="commit"
msg="${1:-}"
case "$msg" in
  --pull) mode="pull"; msg="auto: unsynced changes" ;;
  --auto) mode="auto"; msg="auto: unsynced changes" ;;
  --code) mode="code"; msg="${2:-}"; target="$root" ;;
esac
if [ -z "$msg" ]; then
  echo 'SYNC FAILED: missing commit message. Usage: bash scripts/sync.sh "type: summary" (or --code "type: summary")' >&2
  exit 2
fi

fail() {
  echo "SYNC FAILED: $1" >&2
  # The Stop hook must never block or loop, so auto mode always exits 0.
  if [ "$mode" = "auto" ]; then exit 0; fi
  exit 1
}

# Never hang on the network: no password or host-key prompts, a short SSH
# connect timeout, drop an SSH connection that stops answering for 30 seconds,
# and give up on an HTTPS transfer that stalls for 20 seconds.
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2}"
export GIT_HTTP_LOW_SPEED_LIMIT=1000
export GIT_HTTP_LOW_SPEED_TIME=20

# The vault must be its own repository. Without this check, git would walk up
# to the code repository and commit notes there.
if [ "$mode" != "code" ] && [ ! -e "$target/.git" ]; then
  fail "jarvis-vault is not cloned yet. See DEPLOY.md."
fi
cd "$target" || fail "cannot open $target."

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "this folder is not a git repository."
git remote get-url origin >/dev/null 2>&1 \
  || fail "there is no git remote named origin."
branch="$(git symbolic-ref --quiet --short HEAD)" \
  || fail "not on a branch (detached HEAD). A person needs to fix this by hand."

# One sync at a time, so two syncs never fight over git's index lock.
# This must come before the "in progress" check below, or a second sync
# would see the first one's rebase and give up. The Stop hook waits only
# briefly: if another sync is running, the next sync picks up these changes.
if command -v flock >/dev/null 2>&1; then
  lock_wait=60
  if [ "$mode" = "auto" ]; then lock_wait=20; fi
  exec 9>"$(git rev-parse --git-path jarvis-sync.lock)"
  if ! flock -w "$lock_wait" 9; then
    if [ "$mode" = "auto" ]; then exit 0; fi
    fail "another sync is still running after $lock_wait seconds. Try again in a moment."
  fi
fi

if [ -d "$(git rev-parse --git-path rebase-merge)" ] \
  || [ -d "$(git rev-parse --git-path rebase-apply)" ] \
  || [ -f "$(git rev-parse --git-path MERGE_HEAD)" ]; then
  fail "a merge or rebase is already in progress. A person needs to finish or abort it by hand."
fi

# 1. Commit anything uncommitted.
if [ -n "$(git status --porcelain)" ]; then
  # Capture git's output so line-ending warnings never get mixed into the SYNC line.
  out="$(git add -A 2>&1)" || fail "git add failed: $out"
  out="$(git commit --quiet -m "$msg" 2>&1)" \
    || fail "git commit failed: $out"
fi

pulled=0
pushed=0
attempt=1
while :; do
  # 2. Fetch.
  out="$(git fetch --quiet origin 2>&1)" \
    || fail "could not reach GitHub ($out). Changes are committed locally and will be pushed by the next sync."

  # 3. Rebase onto the remote branch if it has commits we do not have.
  if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    behind="$(git rev-list --count "HEAD..origin/$branch")"
    if [ "$behind" -gt 0 ]; then
      if ! out="$(git rebase --quiet "origin/$branch" 2>&1)"; then
        git rebase --abort >/dev/null 2>&1
        fail "the remote has changes that conflict with the local ones. Nothing was pushed and nothing was lost: the local commit is intact. A person needs to resolve this by hand."
      fi
      pulled=$((pulled + behind))
    fi
    ahead="$(git rev-list --count "origin/$branch..HEAD")"
  elif git rev-parse --verify --quiet HEAD >/dev/null; then
    # First push: the branch does not exist on GitHub yet.
    ahead=1
  else
    # A brand-new clone with no commits at all: nothing to push.
    ahead=0
  fi

  # 4. Push whatever is ahead.
  if [ "$ahead" -eq 0 ]; then break; fi
  if out="$(git push --quiet -u origin "$branch" 2>&1)"; then
    pushed=1
    break
  fi
  # Rejected because the remote moved after our fetch: fetch, rebase, and try again.
  if [ "$attempt" -lt 3 ] && printf '%s' "$out" | grep -qiE 'rejected|fetch first|non-fast-forward|cannot lock ref'; then
    attempt=$((attempt + 1))
    continue
  fi
  fail "git push failed: $out. Changes are committed locally and will be pushed by the next sync."
done

if [ "$pushed" -eq 1 ]; then
  echo "SYNC OK: pushed $(git rev-parse --short HEAD) to origin/$branch"
elif [ "$pulled" -gt 0 ]; then
  echo "SYNC OK: pulled $pulled new commit(s) from origin/$branch"
elif [ "$mode" != "auto" ]; then
  echo "SYNC OK: already up to date"
fi

# On --pull, also bring the code repository up to date, so the server gets new
# scripts and rules. Fast-forward only, and never commit here. git replaces
# changed files with new ones, so this very script keeps running the old copy.
if [ "$mode" = "pull" ] && cd "$root" && [ -e .git ]; then
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" || exit 0
  if [ -n "$(git status --porcelain)" ]; then
    echo "SYNC NOTE: code not updated (local changes to setup files; sync them with --code)"
  elif ! git fetch --quiet 2>/dev/null; then
    echo "SYNC NOTE: code not updated (could not reach GitHub)"
  elif [ "$(git rev-list --count "HEAD..$upstream")" -gt 0 ]; then
    if git merge --ff-only --quiet "$upstream" >/dev/null 2>&1; then
      echo "SYNC NOTE: code updated to $(git rev-parse --short HEAD)"
    else
      echo "SYNC NOTE: code not updated (it has local commits; sync them with --code)"
    fi
  fi
fi

exit 0
