# Vault split, public code repository, and deployment: design

Date: 2026-10-02
Status: written for review

Supersedes the in-chat design behind `specs/2026-10-02-deploy-and-sync-plan.md`, which this work deletes. Everything from that design that still applies is restated here.

## Goal

1. Make the code repository public, with no personal data in it.
2. Move the notes into their own private repository, created from a public template, so anyone can run their own Jarvis.
3. Give Obsidian a vault whose root is a git repository, so desktop and phone sync both work.
4. Provide a step-by-step Ubuntu Server deployment guide, including the tests, and keep the README short.
5. Make `sync.sh` safe when two syncs happen at once, when a push races another device, and when the network stalls.

## Decisions

| Topic | Decision |
|---|---|
| Vault link | `jarvis-vault/` is a separate git repository, cloned into the project folder. The code repository ignores it. No submodule. |
| Repositories | Code: `mssio/jarvis-claude`, public. Template: `mssio/jarvis-vault-template`, public, marked as a GitHub template. Real vault: a private repository created from the template, for example `mssio/jarvis-vault`. |
| Code history | Fresh history. The user reinitialized git locally. Because GitHub keeps force-pushed commits reachable, the old GitHub repository is deleted and recreated empty before the first (normal) push. Claude does not run the force push, because `.claude/settings.json` denies it; the user runs it. |
| About me | Moves out of `AGENTS.md` into `jarvis-vault/about-me.md`, so it lives only in the private vault. The template ships a placeholder. |
| Obsidian | Opens `jarvis-vault/`. The excluded files for setup files are removed, because setup files are no longer inside the vault. `templates/` stays excluded, so the empty template notes stay out of search. |
| Server paths | Project at `~/jarvis`, vault at `~/jarvis/jarvis-vault`, user `vault`, tmux session `jarvis`. |
| Server access | The code repository is cloned over HTTPS, read-only, with no key. The SSH deploy key, with write access, is for the private vault repository only. |
| Docs | `README.md` is an overview of at most 100 lines. `DEPLOY.md` holds the one-time GitHub setup and the server steps, including the tests. `OBSIDIAN.md` covers desktop and phone. |
| Remote Control on boot | An `@reboot` cron line starts `scripts/start-remote.sh` in a detached tmux session. The first run is by hand, to answer the enable prompt. |

## 1. Repository layout

```
jarvis/                        public code repository (mssio/jarvis-claude)
├── AGENTS.md  README.md  DEPLOY.md  OBSIDIAN.md
├── .gitignore                 ignores jarvis-vault/, .claude/settings.local.json, OS files
├── .claude/                   settings.json, skills/summary/
├── scripts/                   sync.sh, start-remote.sh, spending.sh, test-*.sh
├── specs/
└── jarvis-vault/              ignored here; its own repository (template, then the private vault)
    ├── .obsidian/app.json     excludes templates/
    ├── .gitignore             Obsidian workspace files, .trash/, OS files
    ├── README.md              what this template is and how to use it
    ├── about-me.md            placeholder in the template; real text in the private vault
    ├── logs/ people/ events/ tasks/ research/ articles/ docs/ inbox/
    ├── summaries/ spending/ templates/
```

The root `.obsidian/` folder in the code repository is deleted.

## 2. `scripts/sync.sh`

### Targets
- **Default and `--auto`:** the vault repository, `jarvis-vault/`. These are the note commits.
- **`--code "type: summary"`:** the code repository, the project root. Used only where setup files are edited (the authoring machine). Because the vault is ignored there, a code commit never includes notes.
- **`--pull`:**
  - Syncs the vault.
  - Then fast-forwards the code repository if its working tree is clean and it has an upstream. This is how the server gets code updates.
  - It never commits in the code repository. If the fast-forward is not possible, it prints `SYNC NOTE: code not updated (reason)` and the vault result stands.
- **A missing `jarvis-vault/`** gives `SYNC FAILED: jarvis-vault is not cloned yet. See DEPLOY.md.`

### Order
The order is unchanged:
1. Commit anything uncommitted, so local work is safe.
2. Fetch.
3. Rebase the local commits onto the remote, keeping history in one line.
4. Push.

### Hardening
- **Lock:** `flock` on `jarvis-sync.lock` inside the target repository's git folder.
  - It is taken before the "rebase in progress" check, so a second sync never mistakes the first one's rebase for a stuck one.
  - Commit, pull, and code modes wait 60 s. `--auto` waits 20 s, then exits 0 quietly; the next sync picks up its changes.
  - Without `flock`, there is no lock.
- **Push retry:** a rejected push, because the remote moved after the fetch, goes back to step 2. Up to 3 attempts in total. A conflict still aborts the rebase at once, keeping the local commit.
- **No hanging:** `GIT_TERMINAL_PROMPT=0`, SSH with `BatchMode=yes` and `ConnectTimeout=10`, and HTTPS low-speed abort after 20 s.
- **Stop hook:** timeout raised from 60 to 120 s.

### Messages
The `SYNC OK:` and `SYNC FAILED:` wording stays the same. New messages:
- the missing-vault failure
- `SYNC FAILED: another sync is still running after 60 seconds. Try again in a moment.`
- the `SYNC NOTE:` line for code updates

## 3. `AGENTS.md`

- **About me** is replaced by: "At the start of a session, read `jarvis-vault/about-me.md`." The text itself moves to the private vault.
- **Git sync:**
  - Notes sync with `bash scripts/sync.sh "type: summary"`, as now.
  - Changes to setup files sync with `bash scripts/sync.sh --code "type: summary"`.
  - A request that changes both runs both.
- **Intro, Vault structure, and setup files list:**
  - `jarvis-vault/` is its own private git repository, and Obsidian opens it.
  - The setup files are `README.md`, `DEPLOY.md`, `OBSIDIAN.md`, `AGENTS.md`, `.gitignore`, `scripts/`, `.claude/`, and `specs/`.

## 4. `DEPLOY.md`

**Part A: one-time GitHub setup, on your computer**
1. Push the code repository: delete and recreate the GitHub repository if it has old history, then the first commit and a normal push, done by you.
2. Create the public template repository: push `jarvis-vault/` to `jarvis-vault-template`, and tick **Template repository** in its settings.
3. Create the private vault: "Use this template", then **Private**.
4. Replace the local `jarvis-vault/` with a clone of the private vault, and fill in `about-me.md`.

**Part B: Ubuntu Server, steps 1 to 11**

Each step has what it does and why, the commands, and an **Expected:** line.
1. Requirements.
2. Packages (`git tmux curl jq cron ca-certificates openssh-client tzdata`) with a table saying why each is needed, the clock (`timedatectl set-timezone America/Edmonton`), and enabling cron.
3. User `vault`.
4. Install Claude Code.
5. SSH key and deploy key with write access on the private vault.
   - Verify GitHub's host fingerprint with `ssh -T git@github.com` before any sync, because `sync.sh` never answers a host-key prompt.
6. Clone the code over HTTPS to `~/jarvis`, clone the vault over SSH to `~/jarvis/jarvis-vault`, set the git identity, and run `bash scripts/sync.sh --pull`. Expected: `SYNC OK`.
7. Sign in to Claude Code and trust the folder, then run `claude doctor`.
8. Remote Control: the first run by hand, then the `@reboot` cron line.
9. Scheduled summaries: cron.
10. Tests:
    - `test-sync.sh`, all PASS
    - `test-spending.sh`, 35 PASS
    - the three live rate checks
    - phone tests 1 to 10
11. Updating and troubleshooting.

## 5. `OBSIDIAN.md` and `README.md`

- **`OBSIDIAN.md`:**
  - Desktop: open the private vault clone, with the Git plugin and pull intervals.
  - Phone: clone the private vault over HTTPS with a fine-grained token limited to that repository, Contents read and write.
  - Excluded files: `templates/` only.
- **`README.md`**, at most 100 lines:
  - What Jarvis is.
  - How it works, with the diagram updated to show two repositories.
  - Links to the guides.
  - A compact folder table.
  - Everyday phrases.
  - Good to know.
  - What was tested.

## 6. Public readiness

- No personal data in any tracked file of the code repository. Check by searching the tracked files for words from the old About me text and for the email domain; nothing may match. Keep the search terms themselves out of tracked files.
- The template contains no personal data. `about-me.md` is a placeholder.
- Commit identity: recommend GitHub's `noreply` email (`git config user.email "<id>+mssio@users.noreply.github.com"`) before the first commit. This is the user's choice.

## 7. Testing

`scripts/test-sync.sh` builds a throwaway project layout in a temporary folder: a code repository, a `jarvis-vault/` clone of a bare vault remote, and `scripts/sync.sh` copied in. It never touches the real repositories or GitHub.

| # | Case | Expected |
|---|---|---|
| 1 | First push to an empty vault remote | `SYNC OK: pushed` |
| 2 | Nothing to sync | `SYNC OK: already up to date` |
| 3 | A change made on another device | `pulled 1` |
| 4 | Both sides changed different files | Both kept |
| 5 | Same-line conflict | Exit 1, local commit intact, no rebase left |
| 6 | Unreachable remote | Exit 1, commit kept |
| 7 | `--auto` with an unreachable remote | Exit 0 |
| 8 | Missing message | Exit 2 |
| 9 | Push race | Retried, both commits on the remote |
| 10 | Missing `jarvis-vault/` | The DEPLOY.md message |
| 11 | `--code` commits and pushes the code repository | The vault is not included |
| 12 | `--pull` fast-forwards a clean code repository | The code is updated |
| 13 | `--pull` with local code edits | `SYNC NOTE` and exit 0 |
| 14 | Concurrent syncs (needs `flock`) | Both succeed |
| 15 | A leftover lock file (needs `flock`) | Does not block |
| 16 | `--auto` while another sync holds the lock (needs `flock`) | Exits 0 quietly, change kept |

- **On the authoring machine (Windows, no `flock`):** cases 1 to 13 run; 14 to 16 SKIP.
- **On the server:** all 16 run.
- `scripts/spending.sh` and `scripts/test-spending.sh` still run only on the server.
