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
