# Vault Split, Public Code Repository, and Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:**
- Move the notes out into their own repository (template, then a private vault).
- Make the code repository safe to publish.
- Harden `sync.sh` and point it at the vault.
- Replace the long README with a short overview, `DEPLOY.md`, and `OBSIDIAN.md`.

**Architecture:**
- `jarvis-vault/` becomes an independent git repository that the code repository ignores.
- `sync.sh` syncs the vault by default, the code repository with `--code`, and fast-forwards the code repository on `--pull`.
- Its order stays commit, fetch, rebase, push. It gains a `flock` lock, a push-retry loop, and network timeouts.

**Tech Stack:** Bash, git (≥ 2.28), `flock` (util-linux), Markdown, JSON.

**Spec:** `specs/2026-10-02-vault-split-design.md`

## Global Constraints

- **No commits during this plan.** The code repository was reinitialized and has no commits or remote, so `sync.sh` cannot sync it, and `jarvis-vault/` is not a repository yet.
  - Every task ends with "Commit: none".
  - The user makes the first commit and force pushes it (Task 8 hand-off).
  - Claude never runs `git push --force`. `.claude/settings.json` denies it, and that rule stays.
- **Do not run** `scripts/spending.sh` or `scripts/test-spending.sh`. `scripts/test-sync.sh` may run; it only touches `mktemp` folders.
- **Messages:** keep the existing `SYNC OK:` and `SYNC FAILED:` wording. New messages are exactly as in spec §2.
- **`--auto` always exits 0.**
- **Server paths:** project `~/jarvis`, vault `~/jarvis/jarvis-vault`, user `vault`, tmux session `jarvis`.
- **Personal data:** none may remain in any file outside `jarvis-vault/`. The About me text is never written to a tracked file in the code repository or the template.
- **README:** at most 100 lines.

## Review Focus

1. **`jarvis-vault/` exists but is not a git repository.** Without a guard, git would walk up and commit to the code repository. `sync.sh` must check `jarvis-vault/.git` exists before `cd`. Test 10 covers a missing folder; Task 2 step 1 adds the same check for "folder exists, no `.git`" (test 10b).
2. **`--pull` updating `scripts/sync.sh` while it runs.** git replaces files by writing new ones, so the running bash keeps reading the old copy. No test; noted in the code comment.
3. **The lock is taken before the "rebase in progress" check.** Covered by test 14.
4. **A first server connection to github.com.** `BatchMode=yes` refuses the host-key prompt, so `DEPLOY.md` step 5 must accept the key, with `ssh -T`, before step 6's first sync. Checked in Task 5 step 2.
5. **The authoring machine with uncommitted setup files** prints a `SYNC NOTE` on every `--pull`. That is expected and not an error. Covered by test 13.

---

## File map

| File | Status | Responsibility |
|---|---|---|
| `scripts/test-sync.sh` | Create | 16 cases in a throwaway project layout |
| `scripts/sync.sh` | Rewrite | Vault, `--code`, and `--pull` code update; lock, retry, timeouts |
| `.claude/settings.json` | Modify | Stop hook timeout 60 → 120 |
| `jarvis-vault/about-me.md` | Create | Placeholder (template) |
| `jarvis-vault/.obsidian/app.json` | Create (moved) | Excludes `templates/` only |
| `jarvis-vault/.gitignore` | Create | Obsidian workspace files, `.trash/`, OS files |
| `jarvis-vault/README.md` | Create | Template readme |
| `.obsidian/` | Delete | No longer used at the project root |
| `.gitignore` | Modify | Ignore `jarvis-vault/`; drop the Obsidian lines |
| `AGENTS.md` | Modify | About me pointer, two-repository sync rules, setup files |
| `DEPLOY.md` | Create | Part A (GitHub, one-time) and Part B (server, steps 1 to 11) |
| `OBSIDIAN.md` | Create | Desktop and phone |
| `README.md` | Rewrite | Overview, at most 100 lines |
| `specs/2026-10-02-deploy-and-sync-plan.md` | Delete | Superseded |

---

### Task 1: Sync tests (red against the current `sync.sh`)

**Files:** Create `scripts/test-sync.sh`

**Interfaces:**
- Consumes: the `sync.sh` CLI from spec §2: `--pull`, `--auto`, `"type: msg"`, and `--code "type: msg"`; exit codes 0, 1, and 2; the messages.
- Produces: `bash scripts/test-sync.sh`, which prints `PASS`, `FAIL`, or `SKIP name`, then `N passed, M failed, K skipped`, and exits 1 on any failure.

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bash
# Tests for scripts/sync.sh in a throwaway project layout inside a temporary folder.
# It never touches the real repositories or GitHub. Run from the project folder:
#
#   bash scripts/test-sync.sh
#
# Prints PASS, FAIL, or SKIP for each case and exits 1 if any case fails.

set -u
cd "$(dirname "$0")/.." || exit 1
src="$PWD/scripts/sync.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0
skipped=0

ok()   { echo "PASS $1"; pass=$((pass + 1)); }
bad()  { echo "FAIL $1"; shift; printf '  %s\n' "$@"; fail=$((fail + 1)); }
skip() { echo "SKIP $1"; skipped=$((skipped + 1)); }

identity() {
  git -C "$1" config user.name "Test"
  git -C "$1" config user.email "test@example.com"
}

# new_remote NAME: an empty bare repository whose default branch is main
new_remote() { git init --quiet --bare -b main "$tmp/$1.git"; }

# clone_into REMOTE DIR: a clone on branch main with a local identity
clone_into() {
  git clone --quiet "$tmp/$1.git" "$2" 2>/dev/null
  git -C "$2" symbolic-ref HEAD refs/heads/main
  identity "$2"
}

# new_project NAME VAULT_REMOTE: a plain project folder with scripts/sync.sh
# and jarvis-vault/ cloned from the vault remote
new_project() {
  mkdir -p "$tmp/$1/scripts"
  cp "$src" "$tmp/$1/scripts/sync.sh"
  clone_into "$2" "$tmp/$1/jarvis-vault"
}

# run_sync PROJECT ARGS...: runs that project's sync.sh; sets $out and $code
run_sync() {
  out="$(bash "$tmp/$1/scripts/sync.sh" "${@:2}" 2>&1)"
  code=$?
}

v() { echo "$tmp/$1/jarvis-vault"; }

# 1. First push to an empty vault remote
new_remote r1
new_project a r1
echo "hello" > "$(v a)/note.md"
run_sync a "log: first"
if [ "$code" -eq 0 ] && [[ "$out" == "SYNC OK: pushed"* ]] \
  && git --git-dir="$tmp/r1.git" rev-parse --quiet --verify main >/dev/null; then
  ok "1 first push"
else
  bad "1 first push" "exit $code: $out"
fi

# 2. Nothing to sync
run_sync a --pull
if [ "$code" -eq 0 ] && [ "$out" = "SYNC OK: already up to date" ]; then
  ok "2 nothing to sync"
else
  bad "2 nothing to sync" "exit $code: $out"
fi

# 3. Pull a change made on another device
new_project b r1
echo "from b" > "$(v b)/b.md"
run_sync b "log: b"
run_sync a --pull
if [ "$code" -eq 0 ] && [ "$out" = "SYNC OK: pulled 1 new commit(s) from origin/main" ] && [ -f "$(v a)/b.md" ]; then
  ok "3 pull from another device"
else
  bad "3 pull from another device" "exit $code: $out"
fi

# 4. Both sides changed different files
echo "a2" > "$(v a)/a2.md"
run_sync a "log: a2"
echo "b2" > "$(v b)/b2.md"
run_sync b "log: b2"
if [ "$code" -eq 0 ] && [[ "$out" == "SYNC OK: pushed"* ]] && [ -f "$(v b)/a2.md" ]; then
  ok "4 both sides, different files"
else
  bad "4 both sides, different files" "exit $code: $out"
fi

# 5. Same line changed on both sides: conflict, nothing lost
run_sync a --pull
echo "version a" > "$(v a)/note.md"
run_sync a "log: a edits note"
echo "version b" > "$(v b)/note.md"
run_sync b "log: b edits note"
if [ "$code" -eq 1 ] && [[ "$out" == *"conflict"* ]] \
  && [ "$(git -C "$(v b)" log -1 --format=%s)" = "log: b edits note" ] \
  && [ ! -d "$(v b)/.git/rebase-merge" ] && [ ! -d "$(v b)/.git/rebase-apply" ] \
  && [ "$(cat "$(v b)/note.md")" = "version b" ]; then
  ok "5 conflict keeps the local commit and aborts the rebase"
else
  bad "5 conflict keeps the local commit and aborts the rebase" "exit $code: $out"
fi

# 6. Unreachable remote: the change is still committed locally
new_remote r2
new_project c r2
git -C "$(v c)" remote set-url origin "$tmp/does-not-exist.git"
echo "x" > "$(v c)/x.md"
run_sync c "log: x"
if [ "$code" -eq 1 ] && [[ "$out" == *"could not reach GitHub"* ]] \
  && [ "$(git -C "$(v c)" log -1 --format=%s)" = "log: x" ]; then
  ok "6 unreachable remote keeps the local commit"
else
  bad "6 unreachable remote keeps the local commit" "exit $code: $out"
fi

# 7. Auto mode never fails, even with an unreachable remote
echo "y" > "$(v c)/y.md"
run_sync c --auto
if [ "$code" -eq 0 ]; then ok "7 auto mode exits 0 on failure"; else bad "7 auto mode exits 0 on failure" "exit $code: $out"; fi

# 8. Missing commit message
run_sync c
if [ "$code" -eq 2 ] && [[ "$out" == *"missing commit message"* ]]; then
  ok "8 missing message"
else
  bad "8 missing message" "exit $code: $out"
fi

# 9. Push race: the remote moves between our fetch and our push, so the push is retried
new_remote r3
new_project d r3
echo "d" > "$(v d)/d.md"
run_sync d "log: d"
new_project e r3
cat > "$(v d)/.git/hooks/pre-push" <<EOF
#!/usr/bin/env bash
# Test hook: the first time, another clone pushes just before this push lands.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
[ -f "$tmp/raced" ] && exit 0
touch "$tmp/raced"
echo "race" > "$(v e)/race.md"
git -C "$(v e)" add -A
git -C "$(v e)" commit --quiet -m "log: race"
git -C "$(v e)" push --quiet origin main
EOF
chmod +x "$(v d)/.git/hooks/pre-push"
echo "d2" > "$(v d)/d2.md"
run_sync d "log: d2"
remote_log="$(git --git-dir="$tmp/r3.git" log --format=%s main)"
if [ "$code" -eq 0 ] && [[ "$out" == "SYNC OK: pushed"* ]] \
  && [[ "$remote_log" == *"log: race"* ]] && [[ "$remote_log" == *"log: d2"* ]]; then
  ok "9 push race is retried"
else
  bad "9 push race is retried" "exit $code: $out"
fi

# 10. jarvis-vault/ missing, or present but not a repository: refuse, never fall back to another repository
mkdir -p "$tmp/g/scripts"
cp "$src" "$tmp/g/scripts/sync.sh"
run_sync g "log: x"
first_code=$code
first_out=$out
mkdir -p "$tmp/g/jarvis-vault"
echo "n" > "$tmp/g/jarvis-vault/n.md"
run_sync g "log: x"
if [ "$first_code" -eq 1 ] && [[ "$first_out" == *"jarvis-vault is not cloned yet"* ]] \
  && [ "$code" -eq 1 ] && [[ "$out" == *"jarvis-vault is not cloned yet"* ]]; then
  ok "10 missing or non-repository jarvis-vault is refused"
else
  bad "10 missing or non-repository jarvis-vault is refused" "missing: $first_code $first_out" "not a repo: $code $out"
fi

# 11. --code commits and pushes the code repository, never the vault
new_remote code
new_remote r5
clone_into code "$tmp/p"
mkdir -p "$tmp/p/scripts"
cp "$src" "$tmp/p/scripts/sync.sh"
echo "jarvis-vault/" > "$tmp/p/.gitignore"
clone_into r5 "$tmp/p/jarvis-vault"
echo "setup" > "$tmp/p/setup.md"
echo "note" > "$tmp/p/jarvis-vault/n.md"
run_sync p --code "chore: setup"
code_files="$(git --git-dir="$tmp/code.git" ls-tree -r --name-only main 2>/dev/null)"
if [ "$code" -eq 0 ] && [[ "$out" == "SYNC OK: pushed"* ]] \
  && [[ "$code_files" == *"setup.md"* ]] && [[ "$code_files" != *"jarvis-vault"* ]] \
  && [ -n "$(git -C "$tmp/p/jarvis-vault" status --porcelain)" ]; then
  ok "11 --code pushes setup files only"
else
  bad "11 --code pushes setup files only" "exit $code: $out" "files: $code_files"
fi

# 12. --pull fast-forwards a clean code repository
run_sync p "log: n"
clone_into code "$tmp/q"
clone_into r5 "$tmp/q/jarvis-vault"
echo "setup2" > "$tmp/p/setup2.md"
run_sync p --code "chore: setup2"
run_sync q --pull
if [ "$code" -eq 0 ] && [[ "$out" == *"SYNC NOTE: code updated"* ]] && [ -f "$tmp/q/setup2.md" ]; then
  ok "12 --pull updates clean code"
else
  bad "12 --pull updates clean code" "exit $code: $out"
fi

# 13. --pull with local code edits: a note, never a commit
echo "local" > "$tmp/q/local.md"
run_sync q --pull
if [ "$code" -eq 0 ] && [[ "$out" == *"SYNC NOTE: code not updated (local changes"* ]] \
  && [ "$(git -C "$tmp/q" log -1 --format=%s)" = "chore: setup2" ]; then
  ok "13 --pull leaves local code edits alone"
else
  bad "13 --pull leaves local code edits alone" "exit $code: $out"
fi

if command -v flock >/dev/null 2>&1; then
  # 14. Two syncs at the same time in the same vault both succeed
  new_remote r4
  new_project f r4
  echo "f" > "$(v f)/f.md"
  run_sync f "log: f"
  for i in 1 2 3 4; do echo "$i" > "$(v f)/n$i.md"; done
  ( bash "$tmp/f/scripts/sync.sh" "log: one" > "$tmp/o1" 2>&1; echo $? > "$tmp/c1" ) &
  ( bash "$tmp/f/scripts/sync.sh" "log: two" > "$tmp/o2" 2>&1; echo $? > "$tmp/c2" ) &
  wait
  if [ "$(cat "$tmp/c1")" = "0" ] && [ "$(cat "$tmp/c2")" = "0" ] \
    && [ -z "$(git -C "$(v f)" status --porcelain)" ] \
    && [ "$(git -C "$(v f)" rev-parse HEAD)" = "$(git --git-dir="$tmp/r4.git" rev-parse main)" ]; then
    ok "14 concurrent syncs both succeed"
  else
    bad "14 concurrent syncs both succeed" "one: $(cat "$tmp/c1") $(cat "$tmp/o1")" "two: $(cat "$tmp/c2") $(cat "$tmp/o2")"
  fi

  # 15. A lock file left behind by a killed sync does not block
  : > "$(v f)/.git/jarvis-sync.lock"
  echo "z" > "$(v f)/z.md"
  run_sync f "log: z"
  if [ "$code" -eq 0 ] && [[ "$out" == "SYNC OK: pushed"* ]]; then
    ok "15 leftover lock file does not block"
  else
    bad "15 leftover lock file does not block" "exit $code: $out"
  fi

  # 16. --auto while another sync holds the lock: exits 0 quietly, and the change waits for the next sync
  echo "w" > "$(v f)/w.md"
  ( flock 9; sleep 25 ) 9>"$(v f)/.git/jarvis-sync.lock" &
  holder=$!
  sleep 1
  run_sync f --auto
  kill "$holder" 2>/dev/null
  wait "$holder" 2>/dev/null
  if [ "$code" -eq 0 ] && [ -z "$out" ] && [ -n "$(git -C "$(v f)" status --porcelain)" ]; then
    ok "16 auto mode yields to a running sync"
  else
    bad "16 auto mode yields to a running sync" "exit $code: $out"
  fi
else
  skip "14 concurrent syncs (no flock on this machine)"
  skip "15 leftover lock file (no flock on this machine)"
  skip "16 auto mode yields to a running sync (no flock on this machine)"
fi

echo
echo "$pass passed, $fail failed, $skipped skipped"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it against the current `sync.sh`**

Run: `bash scripts/test-sync.sh > "$WS/test-sync-red.txt" 2>&1; tail -n 20 "$WS/test-sync-red.txt"`. `$WS` is the scratch workspace.
Expected: almost everything FAILs, because the current script syncs the project folder, which in this layout is not a repository. Tests 14 to 16 SKIP. The run must finish without hanging.

- [ ] **Step 3: Commit:** none (see Global Constraints).

---

### Task 2: Rewrite `sync.sh`

**Files:**
- Rewrite: `scripts/sync.sh`
- Modify: `.claude/settings.json` (`"timeout": 60` → `120`)

**Interfaces:**
- Consumes: nothing.
- Produces: the CLI and messages from spec §2.

- [ ] **Step 1: Replace `scripts/sync.sh`** (an unborn HEAD with nothing to commit counts as nothing to push)

```bash
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
# connect timeout, and give up on an HTTPS transfer that stalls for 20 seconds.
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
```

- [ ] **Step 2: Raise the Stop hook timeout**

In `.claude/settings.json`, change `"timeout": 60` to `"timeout": 120`.

Run: `powershell -NoProfile -Command "Get-Content .claude/settings.json -Raw | ConvertFrom-Json | Out-Null; 'valid'"`
Expected: `valid`

- [ ] **Step 3: Run the tests**

Run: `bash scripts/test-sync.sh > "$WS/test-sync-green.txt" 2>&1; tail -n 20 "$WS/test-sync-green.txt"`
Expected: `13 passed, 0 failed, 3 skipped`. Tests 14 to 16 run on the server (`DEPLOY.md` step 10).

- [ ] **Step 4: Commit:** none.

---

### Task 3: Turn `jarvis-vault/` into the template, and ignore it in the code repository

**Files:**
- Create: `jarvis-vault/about-me.md`, `jarvis-vault/.gitignore`, `jarvis-vault/README.md`, `jarvis-vault/.obsidian/app.json`
- Delete: `.obsidian/` (project root), `specs/2026-10-02-deploy-and-sync-plan.md`
- Modify: `.gitignore`

- [ ] **Step 1: `jarvis-vault/about-me.md` (placeholder, no personal data)**

```markdown
---
type: about-me
tags: [setup]
---

# About me

Replace this with 2 to 4 lines: who you are, what you are tracking, and how you like answers written. Jarvis reads this note at the start of every session.
```

- [ ] **Step 2: `jarvis-vault/.obsidian/app.json`**

```json
{
  "userIgnoreFilters": [
    "templates/"
  ]
}
```

Then delete the project-root `.obsidian/` folder.

- [ ] **Step 3: `jarvis-vault/.gitignore`**

```gitignore
# Obsidian files that change every time the app is opened
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.obsidian/cache
.trash/

# Operating system files
.DS_Store
Thumbs.db
```

- [ ] **Step 4: `jarvis-vault/README.md`**

```markdown
# Jarvis vault template

The empty Obsidian vault for [Jarvis](https://github.com/mssio/jarvis-claude). Claude writes the notes; you read them in Obsidian.

To use it, click **Use this template** on GitHub, choose **Private**, and follow `DEPLOY.md` in the Jarvis repository. Keep your copy private: it will hold names, birthdays, spending, and daily logs.

Start by filling in `about-me.md`.
```

- [ ] **Step 5: Code repository `.gitignore`**

Replace the whole file with:

```gitignore
# The vault is its own private repository, cloned here (see DEPLOY.md)
jarvis-vault/

# Claude Code settings that belong to one machine only
.claude/settings.local.json

# Operating system files
.DS_Store
Thumbs.db
```

- [ ] **Step 6: Delete the superseded plan**

Delete `specs/2026-10-02-deploy-and-sync-plan.md`.

- [ ] **Step 7: Verify**

Run: `git status --short --ignored jarvis-vault | head -3`
Expected: `!! jarvis-vault/` (ignored).

Run: `ls -A .obsidian 2>&1`
Expected: `No such file or directory`.

- [ ] **Step 8: Commit:** none.

---

### Task 4: `AGENTS.md`

**Files:** Modify `AGENTS.md`

- [ ] **Step 1: Intro paragraph**

Replace the paragraph beginning "This project is a git repository, and its root folder is also the Obsidian vault" with:

```markdown
This project uses two git repositories. The project folder is the public code repository: these rules, `scripts/`, `.claude/`, and the guides. Every note lives in `jarvis-vault/`, a separate private repository cloned inside the project folder and ignored by the code repository. Obsidian opens `jarvis-vault/` on my devices and syncs it through GitHub. A note that is written but not pushed does not exist as far as I am concerned.
```

- [ ] **Step 2: Git sync rules 2 and 3**

Rule 2 becomes:

```markdown
2. **After** every request that created or changed any file, sync before you reply. Notes: `bash scripts/sync.sh "type: short summary"`. Setup files (anything outside `jarvis-vault/`): `bash scripts/sync.sh --code "type: short summary"`. If a request changed both, run both. Run each once per request, after all the files are written.
```

In rule 3, after the sentence about `auto` commits, add: `` `--pull` also updates the code repository when it has no local changes, and prints a `SYNC NOTE:` line about it. A `SYNC NOTE:` is information, not a failure. ``

- [ ] **Step 3: Setup files sentence**

Replace the sentence beginning ``` `README.md`, `AGENTS.md`, `.gitignore`, `scripts/`, `.claude/`, and `.obsidian/` sit in the project folder ``` with:

```markdown
`README.md`, `DEPLOY.md`, `OBSIDIAN.md`, `AGENTS.md`, `.gitignore`, `scripts/`, `.claude/`, and `specs/` sit in the project folder, outside `jarvis-vault/`. They are setup files, not notes, and the code repository is public: never write personal information into them. Do not change them unless I ask.
```

Keep the existing `.gitkeep` sentence after it.

- [ ] **Step 4: About me**

Replace the `## About me` section body (its three lines) with:

```markdown
At the start of every session, read `jarvis-vault/about-me.md`: who I am, what I track, and how I like answers written. Personal details belong there, in the private vault, never in this file.
```

- [ ] **Step 5: Verify**

Run: `grep -n -iE "<words from the old About me>|\.obsidian/" AGENTS.md` (type the words at the prompt; never write them into a tracked file)
Expected: no output.

- [ ] **Step 6: Commit:** none.

---

### Task 5: `DEPLOY.md`

**Files:** Create `DEPLOY.md`

- [ ] **Step 1: Write Part A, the one-time GitHub setup, on your computer**

Each step has one sentence on what and why, a `bash` block, and **Expected:**.
- **A1. Publish the code repository**, from the project folder.
  - Commands:
    - optional: `git config user.email "<id>+mssio@users.noreply.github.com"`
    - `git add -A`
    - `git commit -m "chore: initial public release"`
    - `git remote add origin https://github.com/mssio/jarvis-claude.git`
    - `git push --force -u origin main`
  - Warn that `--force` permanently replaces the old history on GitHub. Do this only for this one reset.
  - Then on GitHub: Settings > General > Change visibility > Public.
- **A2. Publish the template**, from `jarvis-vault/`.
  - Create an empty public repository `jarvis-vault-template` on GitHub, then run:
    - `cd jarvis-vault && git init -b main && git add -A && git commit -m "chore: vault template"`
    - `git remote add origin https://github.com/mssio/jarvis-vault-template.git`
    - `git push -u origin main`
  - Then Settings > General > tick **Template repository**.
- **A3. Create your private vault.** On the template's page: **Use this template** > Create a new repository > name `jarvis-vault`, **Private**.
- **A4. Use the private vault locally.**
  - Commands:
    - `cd ..`
    - `mv jarvis-vault jarvis-vault-template-local`
    - `git clone https://github.com/mssio/jarvis-vault.git jarvis-vault`
  - Fill in `jarvis-vault/about-me.md` with your About me text, then run `bash scripts/sync.sh "chore: about me"`.
  - Expected: `SYNC OK: pushed …`
  - Keep or delete `jarvis-vault-template-local`. It is only needed to update the template later.

- [ ] **Step 2: Write Part B, Ubuntu Server steps 1 to 11**

Same shape per step:
1. **Requirements:**
   - Ubuntu Server 22.04 or 24.04, with 2 vCPU, 4 GB RAM, and 10 GB disk.
   - A Claude Pro or Max plan, because Remote Control needs a subscription, not an API key.
   - Part A done.
2. **Packages and clock:**
   - Commands:
     - `sudo apt update && sudo apt install -y git tmux curl jq cron ca-certificates openssh-client tzdata`
     - `sudo timedatectl set-timezone America/Edmonton`
     - `sudo systemctl enable --now cron`
     - `date`
   - Expected: Mountain Time (MDT or MST).
   - A table of why each package is needed:

     | Package | Needed for |
     |---|---|
     | git | Syncing with GitHub |
     | tmux | Keeping Remote Control running |
     | curl, jq | Bank of Canada exchange rates |
     | cron | Summaries and starting on boot |
     | ca-certificates, openssh-client | Secure connections to GitHub |
     | tzdata | The Mountain Time clock |
3. **User:** `sudo adduser --disabled-password --gecos "" vault`, then `sudo -iu vault`. Everything after this runs as `vault`.
4. **Claude Code:** `curl -fsSL https://claude.ai/install.sh | bash`, then `exec bash -l`, then `claude --version`. Expected: a version number.
5. **SSH key for the private vault:**
   - Run `ssh-keygen -t ed25519 -C "jarvis-homelab" -f ~/.ssh/id_ed25519 -N ""`. There is no passphrase because cron and the Stop hook cannot type one.
   - Run `cat ~/.ssh/id_ed25519.pub`. On GitHub, open the **private vault** repository's Settings > Deploy keys > Add deploy key, paste the key, and tick **Allow write access**. The key works for that one repository only. The code repository needs no key, because it is public and the server only reads it.
   - Run `ssh -T git@github.com`. Before typing `yes`, compare the fingerprint with GitHub's published ED25519 fingerprint `SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU` (docs.github.com, "GitHub's SSH key fingerprints").
   - Expected: `Hi mssio/jarvis-vault! You've successfully authenticated, but GitHub does not provide shell access.`
   - This must happen before step 6, because `sync.sh` never answers a host-key prompt.
6. **Clone both repositories:**
   - Commands:
     - `git config --global user.name "Jarvis Homelab"`
     - `git config --global user.email "jarvis@homelab.local"`
     - `git clone https://github.com/mssio/jarvis-claude.git ~/jarvis`
     - `git clone git@github.com:mssio/jarvis-vault.git ~/jarvis/jarvis-vault`
     - `cd ~/jarvis && bash scripts/sync.sh --pull`
   - Expected: `SYNC OK: already up to date`.
7. **Claude Code sign-in:**
   - Run `cd ~/jarvis && claude`, sign in with the printed link, accept the folder trust prompt, then `/exit`.
   - Run `claude doctor`. Expected: no settings errors.
8. **Remote Control:**
   - First run, by hand: `tmux new -s jarvis`, `bash scripts/start-remote.sh`, answer `y`, and note the session link. Detach with Ctrl+B then D.
   - On boot: run `crontab -e` and add
     ```cron
     @reboot sleep 30 && tmux new-session -d -s jarvis "bash $HOME/jarvis/scripts/start-remote.sh"
     ```
   - Check with `sudo reboot`, reconnect, then `tmux ls`. Expected: a `jarvis:` line, and the "Jarvis" session in the Claude app.
9. **Scheduled summaries:**
   - The three summary cron lines from the current README Part 5, verbatim, with `cd ~/vault` changed to `cd ~/jarvis`.
   - The `%` escaping and staggered-time notes.
   - `tail -n 40 ~/summary-cron.log`.
10. **Tests:**
    - `cd ~/jarvis && bash scripts/test-sync.sh`. Expected: `16 passed, 0 failed, 0 skipped`.
    - `bash scripts/test-spending.sh`. Expected: `35 passed, 0 failed`.
    - Live rate checks, as a table:
      - `bash scripts/spending.sh rate USD 2026-10-01` returns a rate and that date
      - `… rate USD 2026-10-04` (a Sunday) returns Friday `2026-10-02`'s rate
      - `… rate XYZ 2026-10-01` returns `SPENDING ERROR: the Bank of Canada publishes no rate for XYZ`
    - Phone tests 1 to 10, as a table of "Send this" and "Expected", moved verbatim from the current README Part 4, with paths updated for the vault being its own repository.
11. **Updating and troubleshooting:**
    - Updating: every `--pull` fast-forwards `~/jarvis` from GitHub. Changes to `AGENTS.md` or `.claude/` apply after restarting the session: `tmux kill-session -t jarvis`, then the `@reboot` command by hand.
    - Troubleshooting: the bullets from the current README "If something goes wrong", moved verbatim, with paths updated (`~/vault` → `~/jarvis`, and conflicts are resolved inside `~/jarvis/jarvis-vault`). Add three new bullets:
      - `SYNC FAILED: another sync is still running`
      - `SYNC FAILED: jarvis-vault is not cloned yet` (do step 6)
      - `SYNC NOTE: code not updated (local changes …)`: someone edited setup files on the server; inspect with `git -C ~/jarvis status`

- [ ] **Step 3: Check**

Re-read `DEPLOY.md` and confirm:
- Step 5 comes before step 6.
- Every **Expected:** string matches the scripts' real output.
- No `~/vault` paths remain.
- No personal data appears.

Run: `grep -n "~/vault\|Part 4\|Part 5" DEPLOY.md`
Expected: no output.

- [ ] **Step 4: Commit:** none.

---

### Task 6: `OBSIDIAN.md`

**Files:** Create `OBSIDIAN.md`

- [ ] **Step 1: Write it**

Three sections:
1. **Desktop:**
   - Open the `jarvis-vault/` folder as the vault. It is the private vault's own repository.
   - Install the Git community plugin. Turn on pull on startup, with a 5-minute pull interval, and an auto commit-and-sync interval for hand edits.
   - Set the default location for new notes to `inbox`.
2. **Phone:**
   - Install Obsidian and the Git plugin.
   - Create a GitHub fine-grained personal access token: repository access "Only select repositories" set to the private vault, permission Contents read and write.
   - In Obsidian, run the Git plugin's "Clone an existing remote repo" with `https://github.com/mssio/jarvis-vault.git` into the vault root, signing in with your GitHub username and the token.
   - Use the same pull interval as desktop.
   - Mobile sync is not tested yet.
3. **Excluded files:**
   - `.obsidian/app.json` hides `templates/` from search, the quick switcher, the graph, and link suggestions; templates still show in the file list.
   - Change the list under Settings > Files and links > Excluded files.

- [ ] **Step 2: Commit:** none.

---

### Task 7: Short `README.md`

**Files:** Rewrite `README.md`

- [ ] **Step 1: Write it, at most 100 lines**

Sections in order:
1. `# Jarvis`: two sentences, "An Obsidian vault that Claude Code maintains for you…", and a note that the code is public while each user's notes live in their own private vault created from the template.
2. `## How it works`: the diagram updated for two repositories. Phone or browser → Claude Code on Ubuntu Server (Remote Control) → `sync.sh` → the private vault on GitHub → Obsidian on desktop and phone; the public code repository is pulled by the server. Then three bullets: the rule, the script (one sync at a time, retries a rejected push), and the safety net.
3. `## Guides`: `DEPLOY.md` (GitHub setup, Ubuntu Server, tests) and `OBSIDIAN.md` (desktop and phone).
4. `## Folders`: at most 12 rows. `AGENTS.md`, `scripts/`, `.claude/`, `specs/`, `jarvis-vault/` (private vault: logs, people, events, tasks, research, articles, docs, inbox), `jarvis-vault/summaries/`, `jarvis-vault/spending/`, `jarvis-vault/templates/`, `jarvis-vault/about-me.md`.
5. `## Everyday phrases`: the existing table, unchanged.
6. `## Good to know`: one line each for:
   - changing the rules (edit `AGENTS.md`, `sync.sh --code`)
   - no reminders
   - history
   - security: the code repository is public, so keep personal data in the vault; only you can push to either repository; the deploy key reaches the vault only
   - usage
7. `## What was tested`: the existing bullets, plus:
   - `scripts/test-sync.sh`: 13 cases pass on the authoring machine; 16 run on the server
   - not tested yet: the vault split on a real server, and mobile sync

- [ ] **Step 2: Check**

Run: `wc -l README.md`
Expected: 100 or fewer.

Run: `grep -n "Part [1-5]\|~/vault\|\.obsidian/app.json" README.md`
Expected: no output.

- [ ] **Step 3: Commit:** none.

---

### Task 8: Public-readiness check and hand-off

**Files:** none changed.

- [ ] **Step 1: Search tracked-to-be files for personal data**

Run: `grep -rniE "<words from the old About me>|<your email domain>" --exclude-dir=.git --exclude-dir=jarvis-vault .`
Expected: no output.

Run: `grep -rniE "<words from the old About me>|<your email domain>" jarvis-vault`
Expected: no output. The template carries no personal data.

- [ ] **Step 2: Hand off to the user**

Give the user `DEPLOY.md` Part A, steps A1 to A4. Give them their old About me text in the reply, not in any file, to paste into `jarvis-vault/about-me.md` in step A4.
