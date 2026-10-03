# Jarvis

An Obsidian vault that Claude Code maintains for you. You send plain messages from your phone ("log this", "add a task", "spent 14.50 on lunch"); Claude files them as notes, and you read them in Obsidian.

This repository holds the rules and scripts and is public. Your notes live in your own **private** vault, created from the [vault template](https://github.com/mssio/jarvis-vault-template).

## How it works

```
You (phone, browser)
        |  "log this", "add a task", "what is coming up?"
        v
Claude Code on Ubuntu Server   (Remote Control session; reads AGENTS.md)
        |  writes the note, then scripts/sync.sh commits and pushes
        v
Private vault on GitHub        (your notes, full history)
        |  pull
        v
Obsidian on desktop and phone  (reading and browsing)
```

- **The rule.** `AGENTS.md` tells Claude to pull before every request and push after every change.
- **The script.** `scripts/sync.sh` commits, fetches, rebases, and pushes in one step. It runs one sync at a time and retries a push that lost a race with another device.
- **The safety net.** A Stop hook in `.claude/settings.json` runs the same script after every reply, in case Claude forgot.

The server also pulls this public repository on every request, so updates to the rules and scripts arrive on their own.

## Guides

- [DEPLOY.md](DEPLOY.md): GitHub setup, the Ubuntu Server, and the tests.
- [OBSIDIAN.md](OBSIDIAN.md): reading the vault on desktop and phone.

## Folders

| Path | What it holds |
|---|---|
| `AGENTS.md` | The rules Claude follows |
| `scripts/` | `sync.sh`, `start-remote.sh`, `spending.sh`, and their tests |
| `.claude/` | Permissions, the sync hook, and the `/summary` skill |
| `specs/` | Design specs and implementation plans |
| `jarvis-vault/` | Your private vault (its own repository, ignored here) |
| `jarvis-vault/about-me.md` | Who you are and how you like answers; read every session |
| `jarvis-vault/logs/`, `people/`, `events/`, `tasks/` | Daily logs, people and birthdays, events, tasks |
| `jarvis-vault/research/`, `articles/`, `docs/`, `inbox/` | Research, saved articles, how-tos, unsorted |
| `jarvis-vault/summaries/` | Daily, weekly, and monthly summaries |
| `jarvis-vault/spending/` | Monthly spending ledgers (CAD) and categories |
| `jarvis-vault/templates/` | The shape of each note type |

## Everyday phrases

Paths are inside `jarvis-vault/`.

| You say | Claude does |
|---|---|
| "Log this: ..." | Appends a timestamped entry to today's daily log. |
| "Add a task: ..." | Adds a checkbox to `tasks/todo.md`. |
| "I finished ..." | Moves the task to `tasks/done.md` and notes it in today's log. |
| "Tidy my tasks" | Moves tasks you ticked by hand to `tasks/done.md`. |
| "What do I need to do?" | Lists open tasks, soonest due date first. |
| "X's birthday is ..." | Creates or updates the person's note in `people/`. |
| "Whose birthday is coming up?" | Checks the birthday field of every person note. |
| "I have an event on ..." | Creates an upcoming event note in `events/`. |
| "Here is what happened at ..." | Adds notes to the event and marks it done. |
| "What is coming up?" | Lists upcoming events by date. |
| "Research ..." | Writes a note in `research/`. |
| "Save this article: (link)" | Writes a summary with the source link in `articles/`. |
| "Document how I ..." | Writes a how-to in `docs/`. |
| `/summary daily`, `/summary weekly`, `/summary monthly` | Writes a summary in `summaries/`. |
| "Spent 14.50 on lunch, food" | Adds a row to this month's ledger in `spending/`. Asks first for a new category. |
| "Spent 20 USD on …" | Converts to CAD with the Bank of Canada rate and shows the rate. |
| "Delete / change the … entry" | Asks for your yes, showing the date, then updates the ledger. |
| "How much have I spent this month?" | Answers from the ledger. Nothing is written. |
| "Recalculate my spending" | Rewrites the month's totals after you edit a ledger by hand. |

## Good to know

- **Changing the rules.** Edit `AGENTS.md`, then `bash scripts/sync.sh --code "chore: …"`. The server picks it up on its next session.
- **No reminders.** Jarvis stores dates but never notifies you; keep time-sensitive things in your phone calendar too.
- **History.** Every change is a commit, so you can see and undo it on GitHub.
- **Security.** This repository is public: keep personal details in your private vault. The server's deploy key reaches only the vault. In your Claude settings, turn on "Require trusted devices".
- **Usage.** Requests and scheduled summaries count against your Claude plan.

## What was tested

- `scripts/test-sync.sh`: 13 of 16 cases pass on the authoring machine (Windows); the 3 that need `flock` run on the server.
- `.claude/settings.json` is valid JSON; run `claude doctor` on the server (`DEPLOY.md` step 7) to check Claude Code accepts it.
- Not tested yet, all covered by `DEPLOY.md` step 10: the full suites on the server, spending tracking (`scripts/spending.sh` was written without being run), the `/summary` skill and its cron schedule, a live Remote Control session, and mobile sync.
