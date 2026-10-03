# Jarvis

An Obsidian vault that Claude Code maintains for you. You send plain messages from your phone ("log this", "add a task", "spent 14.50 on lunch"); Claude files them as notes, and you read them in Obsidian.

This repository holds the rules and scripts and is public. Your notes and settings live in your own **private** vault.

## Getting started

1. Fork this repository.
2. Create a private vault from the [template](https://github.com/mssio/jarvis-vault-template) (**Use this template** > Private).
3. Follow [DEPLOY.md](DEPLOY.md) to set up an Ubuntu Server.
4. Send `/setup` to Jarvis.

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

- **The rule.** `AGENTS.md` tells Claude to pull before every request, check Jarvis is set up, and push after every change.
- **The script.** `scripts/sync.sh` commits, fetches, rebases, and pushes in one step. It runs one sync at a time and retries a push that lost a race with another device.
- **The safety net.** A Stop hook in `.claude/settings.json` runs the same script after every reply, in case Claude forgot.
- **Updates.** The server pulls your fork on every request, so changes you sync into it arrive on their own.

## /setup

Jarvis does nothing until `/setup` has run. It asks, one question at a time, for your **time zone** (checked against the system's list), your **home currency** (checked against the Bank of Canada; spending is recorded in it, and other currencies are converted with Bank of Canada rates), and three lines **about you**: who you are, what to track, and how you like answers written.

It saves them as `settings.md` and `about-me.md` in your private vault. Run `/setup` again to change anything, or edit `settings.md` as Properties in Obsidian. Dates follow the server clock; `/setup` gives you the command to set it if it differs.

## Guides

- [DEPLOY.md](DEPLOY.md): your copies on GitHub, the Ubuntu Server, `/setup`, and the tests.
- [OBSIDIAN.md](OBSIDIAN.md): reading the vault on desktop and phone.

## Folders

| Path | What it holds |
|---|---|
| `AGENTS.md` | The rules Claude follows |
| `scripts/` | `sync.sh`, `start-remote.sh`, `spending.sh`, and their tests |
| `.claude/` | Permissions, the sync hook, and the `/setup` and `/summary` skills |
| `specs/` | Design specs and implementation plans |
| `jarvis-vault/` | Your private vault (its own repository, ignored here) |
| `jarvis-vault/settings.md` | Time zone and home currency, written by `/setup` |
| `jarvis-vault/about-me.md` | Who you are and how you like answers, written by `/setup` |
| `jarvis-vault/logs/`, `people/`, `events/`, `tasks/` | Daily logs, people and birthdays, events, tasks |
| `jarvis-vault/research/`, `articles/`, `docs/`, `inbox/` | Research, saved articles, how-tos, unsorted |
| `jarvis-vault/summaries/` | Daily, weekly, and monthly summaries |
| `jarvis-vault/spending/` | Monthly spending ledgers and categories |
| `jarvis-vault/templates/` | The shape of each note type |

## Everyday phrases

Paths are inside `jarvis-vault/`.

| You say | Claude does |
|---|---|
| `/setup` | Asks for your time zone, home currency, and About me, and saves them. |
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
| "Spent 20 USD on …" | Converts to your home currency with Bank of Canada rates and shows the rate. |
| "Delete / change the … entry" | Asks for your yes, showing the date, then updates the ledger. |
| "How much have I spent this month?" | Answers from the ledger. Nothing is written. |
| "Recalculate my spending" | Rewrites the month's totals after you edit a ledger by hand. |

## Good to know

- **Changing the rules.** Edit `AGENTS.md` in your fork, then `bash scripts/sync.sh --code "chore: …"`. Never on the server.
- **No reminders.** Jarvis stores dates but never notifies you; keep time-sensitive things in your phone calendar too.
- **History.** Every change is a commit, so you can see and undo it on GitHub.
- **Security.** Forks are public: keep personal details in your private vault. The server's deploy key reaches only the vault. In your Claude settings, turn on "Require trusted devices".
- **Usage.** Requests and scheduled summaries count against your Claude plan.

## What was tested

- `scripts/test-sync.sh`: 13 of 16 cases pass on Windows; the 3 that need `flock` run on the server.
- Not tested yet, all covered by `DEPLOY.md` step 11: the 43 spending tests, Bank of Canada live checks, `/setup` and the setup check, summaries and cron, Remote Control, and mobile sync.
