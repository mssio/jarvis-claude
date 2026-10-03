# Jarvis: vault rules for AI agents

This vault is called Jarvis. You maintain it as my Obsidian vault and AI database. You write the notes. I read, search, and browse them.

This project uses two git repositories. The project folder is the public code repository: these rules, `scripts/`, `.claude/`, and the guides. Every note lives in `jarvis-vault/`, a separate private repository cloned inside the project folder and ignored by the code repository. Obsidian opens `jarvis-vault/` on my devices and syncs it through GitHub. A note that is written but not pushed does not exist as far as I am concerned.

Claude Code reads this file automatically when it starts in the project folder (the folder that contains `jarvis-vault/`). Run every command from there. This file is the single source of truth for how the vault works.

## Git sync (do this on every request)

1. **Before** you read or write anything for a request, run `bash scripts/sync.sh --pull` so you are working on the latest notes. I sometimes edit notes by hand on another device.
2. **After** every request that created or changed any file, sync before you reply. Notes: `bash scripts/sync.sh "type: short summary"`. Setup files (anything outside `jarvis-vault/`): `bash scripts/sync.sh --code "type: short summary"`. If a request changed both, run both. Run each once per request, after all the files are written.
3. The commit message starts with one of these types: `log`, `task`, `person`, `event`, `research`, `article`, `doc`, `inbox`, `summary`, `spending`, `setup`, `chore`. You may also see `auto: unsynced changes` commits in the history. `scripts/sync.sh` makes those itself when it finds uncommitted changes, such as hand edits from Obsidian. Never use `auto` yourself. `--pull` also updates the code repository when it has no local changes, and prints a `SYNC NOTE:` line about it. A `SYNC NOTE:` is information, not a failure. Example: `bash scripts/sync.sh "person: add Jane Doe with birthday"`. Do not put private details in the message beyond what is needed to recognise the change.
4. Do not tell me something is saved until the script prints `SYNC OK`. If it prints `SYNC FAILED`, tell me the exact message, and tell me the note is written on the server but not yet on GitHub.
5. If the sync fails, run it one more time at most. Never force push, never run `git reset`, `git clean`, `git rebase`, or `git checkout` to discard anything, and never rewrite history. A failed sync loses nothing: the change stays committed locally and the next successful sync pushes it.
6. If the script reports a conflict, stop and tell me. Do not try to resolve it yourself.
7. A request that only reads notes needs step 1 only.

Use `scripts/sync.sh` for all syncing. Do not run `git add`, `git commit`, `git pull`, or `git push` yourself.

## Setup (check on every request)

After step 1 of Git sync, read `jarvis-vault/settings.md` and `jarvis-vault/about-me.md`.

If `settings.md` is missing, or its frontmatter has no `timezone` (or one containing spaces) or no 3-letter `currency`, reply only:

`Jarvis isn't set up yet. Run /setup to choose your time zone and currency.`

and do nothing else for that request. The only exceptions are `/setup` itself and questions about how to set up Jarvis.

`settings.md` and `about-me.md` are written by `/setup` (`.claude/skills/setup/SKILL.md`). Use their values wherever these rules mention the time zone, the home currency, or how I like answers written.

## Vault structure

Every note path in this file is inside `jarvis-vault/`. For example, `tasks/todo.md` means `jarvis-vault/tasks/todo.md`. Never write notes outside `jarvis-vault/`.

- `logs/daily/YYYY-MM-DD.md` : one file per day, timestamped entries appended in order
- `people/` : one note per person, named `firstname-lastname.md`
- `events/` : one note per event or meeting, named `YYYY-MM-DD-title.md`
- `tasks/todo.md` : all open tasks as checkboxes
- `tasks/done.md` : completed tasks with their completion date
- `research/` : one note per topic I ask you to look into
- `articles/` : summaries of things I save, always with the source URL
- `docs/` : how-to and process documentation
- `inbox/` : anything you are unsure where to file
- `settings.md`, `about-me.md` : written by `/setup`; read on every request
- `spending/YYYY-MM.md` : one spending ledger per month, in the home currency; `spending/categories.md` : the approved spending categories
- `summaries/daily/`, `summaries/weekly/`, `summaries/monthly/` : generated summaries, written only by the `summary` skill (`.claude/skills/summary/SKILL.md`, run with `/summary`). A week runs Monday to Sunday.
- `templates/` : the shape of each note type. Copy from these, never edit them unless I ask.

`README.md`, `DEPLOY.md`, `OBSIDIAN.md`, `AGENTS.md`, `.gitignore`, `scripts/`, `.claude/`, and `specs/` sit in the project folder, outside `jarvis-vault/`. They are setup files, not notes, and the code repository is public: never write personal information into them. Do not change them unless I ask. On the Ubuntu server (project folder `/home/vault/jarvis`), never change setup files even if I ask: the server can only read the code repository, so a change there could never be pushed and would block code updates. Tell me to make that change from my computer instead. Leave the `.gitkeep` files in place: they keep empty folders in the repository.

## Rules for writing

1. Every note is a `.md` file with YAML frontmatter. The default fields are `type`, `created`, `updated`, `tags`, `source`. People and event notes use the fields listed in their own sections below.
2. Use the matching file in `templates/` as the starting shape for a new note.
3. File names are lowercase with hyphens, no spaces. Dates are `YYYY-MM-DD` and times are 24-hour `HH:MM`, both in the time zone from `settings.md`. The server clock is set to it, so run `date` to get the current date and time instead of assuming it.
4. When I say "log this", append an entry to today's daily log in the form `- HH:MM entry text`. Create the file from `templates/daily-log.md` if it does not exist yet. Never rewrite or delete earlier entries.
5. Before creating a note, check whether one already exists on that topic. If it does, update it instead and set `updated` to today's date.
6. Link related notes with `[[wikilinks]]`. When a log or note mentions a person who has a note in `people/`, link to it.
7. Record only what I gave you or what a source says. Label anything you inferred as "Inferred:". Do not fill gaps with guesses.
8. If the folder, date, or topic is ambiguous, file it in `inbox/` and tell me.
9. After writing and syncing, reply with one line: the file path, what changed, and whether it was pushed. The exceptions are the `summary` and `setup` skills, which have their own reply formats. Follow the skill.

## People notes

- Frontmatter fields: `type` (person), `name`, `birthday`, `relationship`, `tags`, `created`, `updated`.
- When I mention someone's birthday, create or update their note in `people/` and set the `birthday` field (`YYYY-MM-DD`, or `MM-DD` if I don't know the year). Do not record it only in the daily log.
- Put everything else I tell you about the person under a `## Notes` heading as dated bullet points.

## Tasks

- When I say "add a task" or mention something I need to do, add it to `tasks/todo.md` in the form `- [ ] task (due: YYYY-MM-DD) (added: YYYY-MM-DD)`. Leave out the due part if I gave no date.
- When I say a task is done, remove it from `tasks/todo.md`, add it to `tasks/done.md` in the form `- [x] task (done: YYYY-MM-DD)`, and append a one-line entry to today's daily log.
- I may tick a checkbox by hand in Obsidian. When I say "tidy my tasks", move every ticked item in `tasks/todo.md` to `tasks/done.md` with today's date.
- When I ask what I need to do, read `tasks/todo.md` and list tasks with due dates first, soonest at the top.
- If a task relates to a person, event, or note, link it with `[[wikilinks]]`.

## Events

- Frontmatter fields: `type` (event), `title`, `date`, `time`, `location`, `status`, `people`, `tags`, `created`, `updated`.
- When I mention an event or meeting I will attend, create a note in `events/` with status `upcoming` and fill in date, time, and location if I gave them.
- If there is something I need to prepare, add it to `tasks/todo.md` and link it to the event note.
- After the event, when I share what happened, add it under `## Notes` in the same file and set status to `done`.
- If an event is cancelled, set status to `cancelled`. Do not delete the note.
- If I mention people attending, list them in the `people` field and link their notes from `people/`.
- When I ask what is coming up, list events with status `upcoming` by date, soonest first.

## Spending

Ledgers are `spending/YYYY-MM.md`, one per month, named after the month the spending happened (not when I told you). Create a missing one from `templates/spending.md`. All amounts are in the home currency (`currency` in `settings.md`), with two decimals. When you create a ledger, fill its `currency:` field and the Totals line with that code. Never do the arithmetic yourself: use `bash scripts/spending.sh`, and copy its numbers exactly.

**Adding**, for example "spent 14.50 on lunch, food":
1. Amount: required. Ask if missing or unclear.
2. Category: required. If missing, ask and list the categories in `spending/categories.md`. Match ignoring case and store lowercase. If it is not on the list, ask `New category 'snacks'? Existing: food, transport. Yes, or pick one.` and save nothing until I answer. You may suggest a likely existing category, but never pick one yourself. On yes, add `- snacks` to `spending/categories.md`.
3. Date: today if I gave none, and say `(today)` in the reply. Work out "yesterday", "last Friday", and so on with `date`.
4. Description: optional, from what I said. Replace any `|` with `/`.
5. Another currency: run `bash scripts/spending.sh rate CUR DATE`, then `bash scripts/spending.sh convert AMOUNT RATE`. Put `AMOUNT CUR × RATE (BoC RATE-DATE)` in the Original column. If `rate` fails for any reason (no rate for that currency, network down, and so on), save nothing. Tell me the error and ask: `No Bank of Canada rate for XYZ. What is 1 XYZ in <home>?` When I give a rate, run `convert` with it, then confirm before saving: `Save Friday 2026-10-02 · 100.00 XYZ × 0.0123 (rate given) = 1.23 <home> · food · "dinner"? Yes / no`. Save only after my yes, recording `(rate given)` in place of `(BoC …)`.
6. If the ledger already exists, first run `bash scripts/spending.sh total jarvis-vault/spending/YYYY-MM.md`. If it reports a bad row, stop: tell me the line, and save nothing. Otherwise add the row in date order (after rows with the same date). Run `total` again, and rewrite the `## Totals` section from its output: `- **Total: X <home>** (N entries)`, then one `- category: amount (pct%)` line per CATEGORY line.
7. Sync with type `spending`, then reply in one line, for example `spending/2026-10.md: 14.50 <home> food "lunch" on Friday 2026-10-02 (today). October total 76.20 <home>. Pushed.` For a converted entry, add the rate, for example `45.00 USD × 1.3712 (BoC 2026-10-01) = 61.70 <home>`.

**Editing, deleting, rate corrections, and category renames: always ask first.** Every change to an existing row needs my yes, even when only one row matches. The question always shows the date with its weekday, for example:
- `Delete this entry? Friday 2026-10-02 · 14.50 <home> · food · "lunch". Yes / no`
- `Change this entry? Saturday 2026-10-03 · shopping · "headphones": 61.70 → 59.99 <home>. Yes / no`
- `Rename category food → eating out? This changes 12 entries from Thursday 2026-10-01 to Wednesday 2026-10-28 across 1 month. Yes / no`

If more than one row matches, list them with their dates and weekdays and ask which one. A rate correction recalculates the home-currency amount with `convert` and updates Original. After the change, recalculate Totals in every ledger touched, then sync. Never remove or rename a category unless I ask. A rename updates `spending/categories.md` and every matching row in every month.

**Other:**
- Do not add spending to the daily log.
- "Recalculate my spending": rerun `total` on the current month's ledger and rewrite Totals. Use this after I edit a ledger by hand.
- Questions like "how much have I spent this month?" are answered from `total` output. Nothing is written.
- If `total` reports a bad row, tell me the line and do not change anything until it is fixed. Edits, deletes, and renames also run `total` first, before changing anything.

## Rules for answering

- When I ask about my data, read the relevant notes first, answer from them, and name the notes you used.
- For questions like "whose birthday is coming up?", check the `birthday` field of every note in `people/`.
- If the vault does not contain the answer, say so instead of answering from general knowledge.

## About me

At the start of every session, read `jarvis-vault/about-me.md`: who I am, what I track, and how I like answers written. Personal details belong there, in the private vault, never in this file. It is written by /setup.
