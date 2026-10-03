# Deploying Jarvis

Part A makes your own copies on GitHub (once, in a browser). Part B sets up the Ubuntu Server that runs Jarvis, including `/setup` and the tests.

Jarvis uses three repositories:

| Repository | Visibility | What it is | The server needs |
|---|---|---|---|
| `mssio/jarvis-claude` | Public | The upstream code: rules, scripts, skills, guides | Nothing; you fork it |
| `<your-github-user>/jarvis-claude` | Public | Your fork, which your server pulls | Read access (HTTPS, no key) |
| `<your-github-user>/jarvis-vault` | **Private** | Your notes, created from `mssio/jarvis-vault-template` | Read and write (an SSH deploy key) |

Replace `<your-github-user>` everywhere below with your GitHub username.

---

## Part A: Make your own copies (once, in a browser)

### A1. Fork the code

Open `https://github.com/mssio/jarvis-claude` and click **Fork**. Forks of public repositories are public, which is fine: the code holds no personal data. Your server pulls from your fork, so nobody else's changes reach it until you choose to sync (step 12).

### A2. Create your private vault

Open `https://github.com/mssio/jarvis-vault-template`, then **Use this template** > **Create a new repository**. Name it `jarvis-vault` and choose **Private**. It will hold names, birthdays, spending, and daily logs.

### A3. A computer for editing the rules (optional)

Only needed if you want to change the rules or scripts in your fork:

```bash
git clone https://github.com/<your-github-user>/jarvis-claude.git jarvis
cd jarvis
git clone https://github.com/<your-github-user>/jarvis-vault.git jarvis-vault
```

**Expected:** both clones succeed. Edits to the rules sync with `bash scripts/sync.sh --code "chore: …"`.

---

## Part B: Ubuntu Server

Run each step in order. Steps 1 and 2 use `sudo`; everything from step 3 on runs as the `vault` user.

### 1. Requirements

- Ubuntu Server 22.04 or 24.04, with 2 vCPU, 4 GB RAM, and 10 GB disk.
- A Claude Pro or Max plan. Remote Control needs a subscription, not an API key.
- Part A done.

### 2. Packages and clock

```bash
sudo apt update && sudo apt install -y git tmux curl jq cron ca-certificates openssh-client tzdata
sudo timedatectl set-timezone <Area/City>    # for example America/Edmonton
sudo systemctl enable --now cron
date
```

**Expected:** `date` shows your local time. Jarvis uses this clock for every date and time it writes; step 9 records the same zone in your settings.

| Package | Needed for |
|---|---|
| git | Syncing with GitHub |
| tmux | Keeping Remote Control running in the background |
| curl, jq | Bank of Canada exchange rates |
| cron | Scheduled summaries and starting Remote Control on boot |
| ca-certificates, openssh-client | Secure connections to GitHub |
| tzdata | Time zone data |

### 3. A dedicated user

```bash
sudo adduser --disabled-password --gecos "" vault
sudo -iu vault
```

**Expected:** the prompt shows `vault@…`. Stay as this user for the rest of the guide.

### 4. Claude Code

```bash
curl -fsSL https://claude.ai/install.sh | bash
exec bash -l
claude --version
```

**Expected:** a version number.

### 5. SSH key for your private vault

The server writes notes to your private vault, so it needs a key for that one repository. The key has no passphrase because cron and the sync hook cannot type one.

```bash
ssh-keygen -t ed25519 -C "jarvis-server" -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub
```

Copy the printed line. On GitHub, open your **private `jarvis-vault`** repository > Settings > Deploy keys > Add deploy key, paste it, and tick **Allow write access**. A deploy key reaches only that repository. Your fork needs no key: it is public and the server only reads it.

Now connect once to accept GitHub's host key:

```bash
ssh -T git@github.com
```

Before typing `yes`, check the fingerprint matches GitHub's published ED25519 fingerprint, `SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU` (see "GitHub's SSH key fingerprints" on docs.github.com).

**Expected:** `Hi <your-github-user>/jarvis-vault! You've successfully authenticated, but GitHub does not provide shell access.`

Do this before step 6: the sync script never answers a host-key prompt, so it would fail until the key is accepted.

### 6. Clone both repositories

```bash
git config --global user.name "Jarvis Server"
git config --global user.email "jarvis@localhost"
git clone https://github.com/<your-github-user>/jarvis-claude.git ~/jarvis
git clone git@github.com:<your-github-user>/jarvis-vault.git ~/jarvis/jarvis-vault
cd ~/jarvis && bash scripts/sync.sh --pull
```

**Expected:** `SYNC OK: already up to date`.

### 7. Sign in to Claude Code

```bash
cd ~/jarvis && claude
```

Sign in with the link it prints (the server has no browser, so open it on another device). Accept the prompt to trust the folder, which lets the permissions and the sync hook in `.claude/settings.json` apply. Then type `/exit` and run:

```bash
claude doctor
```

**Expected:** no settings errors.

### 8. Remote Control

The first run is by hand, because it asks you to enable Remote Control:

```bash
tmux new -s jarvis
bash scripts/start-remote.sh
```

Answer `y`, note the session link (press space for a QR code), then detach with Ctrl+B then D.

To start it on every boot, run `crontab -e` and add:

```cron
@reboot sleep 30 && tmux new-session -d -s jarvis "PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin bash $HOME/jarvis/scripts/start-remote.sh"
```

The 30-second wait gives the network time to come up. The `PATH=` part is needed because cron starts with a minimal `PATH` that does not include `~/.local/bin`, where `claude` is installed. Check it with `sudo reboot`, reconnect, then:

```bash
tmux ls
```

**Expected:** a line starting with `jarvis:`, and the session named "Jarvis" in the Claude app. Attach any time with `tmux attach -t jarvis`.

### 9. Run `/setup`

Until this is done, every request gets the reply `Jarvis isn't set up yet. Run /setup to choose your time zone and currency.`

Open the "Jarvis" session in the Claude app (or run `claude` in `~/jarvis` on the server) and send `/setup`. It asks one question at a time:

| It asks | Example answer | What it does with it |
|---|---|---|
| Time zone, suggesting the server's | `yes` (or `America/Toronto`) | Checks it is a real time zone name |
| Home currency | `CAD` | Checks the Bank of Canada publishes it; spending is recorded in it |
| Who you are | `A software developer` | About me |
| What to keep track of | `Meetings, tasks, birthdays, spending` | About me |
| How you like answers written | `Short bullet points, dates first` | About me |

It writes `settings.md` and `about-me.md` in your private vault and pushes them.

**Expected:** a reply ending with:

```
Saved: time zone <zone>, currency <CODE>, About me (3 lines).
Jarvis is ready.
```

If the reply includes a `sudo timedatectl set-timezone …` line, your server clock is in a different zone: run that line (as a user with sudo) so dates come out right.

Run `/setup` again any time to change a value; it shows the current ones first and keeps what you don't change. You can also edit `settings.md` as Properties in Obsidian.

### 10. Scheduled summaries

Cron runs with a minimal `PATH`, so find Claude Code's full path first:

```bash
command -v claude
```

It is usually `/home/vault/.local/bin/claude`. Run `crontab -e` again and add these lines (use your path if it differs):

```cron
# Jarvis summaries. Times are the server's time zone (step 2).
# Daily: every day at 06:00, for today.
0 6 * * * cd ~/jarvis && /home/vault/.local/bin/claude -p "Run the summary skill for the daily period, for today." --permission-mode acceptEdits >> ~/summary-cron.log 2>&1

# Weekly: Sunday at 19:00, for the week that ends today (Monday to Sunday).
0 19 * * 0 cd ~/jarvis && /home/vault/.local/bin/claude -p "Run the summary skill for the weekly period, for the week containing $(date +\%F)." --permission-mode acceptEdits >> ~/summary-cron.log 2>&1

# Monthly: the 1st at 06:30, for the month that just ended.
30 6 1 * * cd ~/jarvis && /home/vault/.local/bin/claude -p "Run the summary skill for the monthly period, for the month containing $(date -d yesterday +\%F)." --permission-mode acceptEdits >> ~/summary-cron.log 2>&1
```

- `claude -p` runs one request without a chat window. It uses the sign-in from step 7, and the sync hook pushes the result.
- The prompt asks for the skill in words because slash commands may not run in `-p` mode.
- In a crontab, `%` is special, so dates are written as `\%F`.
- The monthly run is on the 1st, because cron has no "last day of the month". The 06:00 and 06:30 runs are staggered.
- If `/setup` has not been run, each summary stops with `Jarvis isn't set up yet. Run /setup to choose your time zone and currency.` in the log.

**Expected:** the next morning, `tail -n 40 ~/summary-cron.log` ends with the summary path and `SYNC OK`.

### 11. Tests

**Script tests** (offline):

```bash
cd ~/jarvis
bash scripts/test-sync.sh
bash scripts/test-spending.sh
```

**Expected:** `16 passed, 0 failed, 0 skipped`, then `43 passed, 0 failed`. A `FAIL` line shows what was expected and what came out.

**Live exchange rates** (these assume `/setup` saved CAD as the home currency):

| Run | Expected |
|---|---|
| `bash scripts/spending.sh check-currency USD` | `ok` |
| `bash scripts/spending.sh check-currency XYZ` | `SPENDING ERROR: the Bank of Canada publishes no rate for XYZ` |
| `bash scripts/spending.sh rate USD 2026-10-01` | A rate like `1.3xxx` and `2026-10-01` |
| `bash scripts/spending.sh rate USD 2026-10-04` (a Sunday) | Friday's rate, dated `2026-10-02` |
| `bash scripts/spending.sh rate XYZ 2026-10-01` | `SPENDING ERROR: the Bank of Canada publishes no rate for XYZ` |

**Cross rates** (a home currency other than CAD). These use a throwaway settings file, so your real settings are not touched:

```bash
printf -- '---\ncurrency: EUR\n---\n' > /tmp/eur-settings.md
JARVIS_SETTINGS=/tmp/eur-settings.md bash scripts/spending.sh rate USD 2026-10-01
JARVIS_SETTINGS=/tmp/eur-settings.md bash scripts/spending.sh rate CAD 2026-10-01
rm /tmp/eur-settings.md
```

**Expected:** each prints a rate with 6 decimals (USD to EUR a little below 1, CAD to EUR roughly 0.6 to 0.7) and the date `2026-10-01`.

**From your phone** (Claude app, session "Jarvis"), one at a time. After each write, check a new commit appears in your private vault on GitHub.

| # | Send this | Expected |
|---|---|---|
| 1 | `Log this: set up Jarvis today.` | A new file in `logs/daily/`, a commit starting with `log:` |
| 2 | `Add a task: back up the vault, due next Friday.` | A new checkbox line in `tasks/todo.md` |
| 3 | `Jane Doe's birthday is March 18. She is a friend from school.` | `people/jane-doe.md` with the birthday in its frontmatter |
| 4 | `I have a career fair on October 20 at 1 pm.` | A new file in `events/` with status "upcoming" |
| 5 | `What is coming up, and what do I need to do?` | An answer naming the files it used; no new commit |
| 6 | `/summary weekly` | A file in `summaries/weekly/` titled with the Monday and Sunday dates |
| 7 | `Spent 14.50 on lunch, food.` | Asks to confirm the new category "food"; after yes, the month's ledger in `spending/` has one row and Totals 14.50 |
| 8 | `Spent 20 USD on a book, food.` | The reply shows the Bank of Canada rate; the row's Original column shows `20.00 USD × …` |
| 9 | `Delete the book.` | Asks first, showing the date with its weekday; after yes, Totals is back to 14.50 |
| 10 | `Spent 100 XYZ on dinner, food.` | Says there is no XYZ rate and asks for one; shows the converted entry with its date and asks for yes; saves with `(rate given)` |
| 11 | On the server, `mv ~/jarvis/jarvis-vault/settings.md /tmp/`, then send `What do I need to do?` | `Jarvis isn't set up yet. Run /setup …` and nothing else |
| 12 | `mv /tmp/settings.md ~/jarvis/jarvis-vault/`, then send `/setup` and keep every value | The same values, then `Jarvis is ready.` |

### 12. Updating and troubleshooting

**Updating.** To get upstream changes, open your fork on GitHub and click **Sync fork**. Every request starts with `sync.sh --pull`, which fast-forwards `~/jarvis` from your fork, so the server picks them up on its next request. Changes to `AGENTS.md` or `.claude/` take effect when the session restarts:

```bash
tmux kill-session -t jarvis
tmux new-session -d -s jarvis "bash $HOME/jarvis/scripts/start-remote.sh"
```

**If something goes wrong:**

- **"Jarvis isn't set up yet."** Run `/setup` (step 9).
- **Times off by whole hours.** The server clock is in a different zone from `settings.md`. Run the `sudo timedatectl set-timezone …` line that `/setup` printed, or redo step 2.
- **SYNC FAILED.** Nothing is lost: the note is committed in `~/jarvis/jarvis-vault` and the next successful sync pushes it. The message says why, usually GitHub unreachable or a deploy key without write access.
- **SYNC FAILED: another sync is still running.** A sync took more than 60 seconds, for example a slow network during a cron summary. Try again; if it repeats, check for a stuck process with `ps aux | grep sync.sh`.
- **SYNC FAILED: jarvis-vault is not cloned yet.** Do step 6.
- **SYNC NOTE: code not updated (local changes …).** Someone edited setup files on the server. Inspect with `git -C ~/jarvis status`; the server should not change setup files.
- **A conflict.** You and Claude changed the same line of the same note. Run `cd ~/jarvis/jarvis-vault && git pull --rebase`, fix the marked lines, then `git add -A && git rebase --continue && git push`.
- **The session is gone from the app.** Check `tmux ls`. `start-remote.sh` restarts after a network drop, and the `@reboot` line restarts it after a reboot.
- **Claude asks permission for every edit.** The folder was not trusted. Run `claude` in `~/jarvis` once and accept the trust prompt; `claude doctor` shows settings errors.
- **No scheduled summaries.** Read `~/summary-cron.log`. Empty: check `systemctl status cron`. `claude: not found`: fix the path in `crontab -e`. `isn't set up yet`: run `/setup`. Otherwise run the same `claude -p "…"` line by hand in `~/jarvis` to see what happens.
