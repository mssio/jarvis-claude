---
name: summary
description: Generate a daily, weekly, or monthly summary note of the Jarvis vault (events, birthdays, tasks, daily logs, inbox) and save it in jarvis-vault/summaries/. Use only when the user runs /summary, or explicitly asks to generate or regenerate a daily, weekly, or monthly summary (including from a scheduled cron prompt). Do not use it to answer ordinary questions such as "what is coming up?".
argument-hint: daily|weekly|monthly [YYYY-MM-DD]
allowed-tools: Read, Glob, Grep, Write, Edit, Bash(date *), Bash(bash scripts/sync.sh *), Bash(bash scripts/spending.sh *)
---

# Summary

Arguments: `$ARGUMENTS`

The first argument is the period: `daily`, `weekly`, or `monthly`. The optional second argument is a reference date `YYYY-MM-DD`. Without it, the reference date is today. If the period is missing or not one of the three, stop and ask which one I want.

Follow `AGENTS.md` for everything not covered here: sync before and after, the time zone from settings.md, wikilinks, and record only what the notes say. All note paths below are inside `jarvis-vault/`. Run every command from the project folder.

## 1. Pull and check setup

Run `bash scripts/sync.sh --pull`. Then read `jarvis-vault/settings.md`. If it is missing, or has no `timezone` or `currency`, reply `Jarvis is not set up yet. Run /setup.` and stop: write no note and do not sync. A scheduled run prints this to its log.

## 2. Work out the dates with `date`, never by hand

Set `D` to the reference date and `T` to today (`date +%F`).

Run each `date` command on its own with the real dates typed in: no `$(...)`, pipes, `&&`, or variables. A scheduled run has nobody to approve a command, and only plain `date` commands are pre-approved. Never work a date out by hand.

**Daily** — the period is the single day `D`.
- Recap day: `date -d "D -1 day" +%F`
- Look-ahead: the 7 days after `D`, `date -d "D +1 day" +%F` to `date -d "D +7 days" +%F`

**Weekly** — weeks run Monday to Sunday (ISO weeks).
- Start (Monday): first run `date -d D +%u`, which prints the weekday number `N` (1 is Monday, 7 is Sunday). Then run `date -d "D -(N-1) days" +%F` with the number filled in, for example `date -d "2026-10-02 -4 days" +%F` when `N` is 5.
- End (Sunday): `date -d "START +6 days" +%F`
- Week label: `date -d START +%G-W%V` (for example `2026-W40`)
- Look-ahead: the next week, `date -d "START +7 days" +%F` to `date -d "START +13 days" +%F`

**Monthly** — the calendar month that contains `D`.
- Start: `date -d D +%Y-%m-01`
- End: `date -d "START +1 month -1 day" +%F`
- Month label: `date -d START +%Y-%m`, month name: `date -d START "+%B %Y"`
- Look-ahead: the next month, `date -d "START +1 month" +%F` to `date -d "START +2 months -1 day" +%F`

Get the weekday name of any date with `date -d DATE +%A`. In the note, write a date with its weekday wherever it appears, for example `Monday 2026-09-28`.

## 3. Collect

Read only the notes; do not guess. For each item, keep a `[[wikilink]]` to its note.

- **Events**: every note in `events/`. Use its `date`, `time`, `location`, `status`, and `people`.
  - In the period: all events dated inside it, any status. Mark `done` and `cancelled` ones as such.
  - In the look-ahead: events with status `upcoming`.
- **Birthdays**: the `birthday` field of every note in `people/`. Birthdays repeat every year, so match on month and day only.
  - A `YYYY-MM-DD` birthday shows the age the person turns on that occurrence (occurrence year minus birth year). An `MM-DD` birthday shows no age.
  - A `02-29` birthday falls on `02-28` in years that are not leap years.
  - When the range crosses a year end, check both years.
- **Tasks** from `tasks/todo.md` and `tasks/done.md`:
  - Due in the period: open tasks whose `due` date is inside it.
  - Due in the look-ahead: open tasks whose `due` date is inside it.
  - Overdue: open tasks whose `due` date is before today `T`.
  - Completed in the period: tasks in `done.md` whose `done` date is inside the period (for daily, the recap day). Also list any ticked `- [x]` items still in `todo.md` under "Ticked, not yet tidied", without a date.
  - No due date: count the open tasks without a `due` part and list the 5 oldest by `added` date.
- **Daily logs**: the files in `logs/daily/` for every day in the period (for daily, the recap day). Write a few highlight bullets, each pointing to its log file. Do not copy every entry.
- **Inbox**: list every note in `inbox/` except `.gitkeep`.
- **Spending** (monthly only): if `spending/MONTH.md` exists for the month label, run `bash scripts/spending.sh total jarvis-vault/spending/MONTH.md`. Use only its output, never the ledger's stored Totals section. For the previous month, get the label with `date -d "START -1 month" +%Y-%m`. If that ledger exists, run `total` on it too, then `bash scripts/spending.sh delta CURRENT PREVIOUS` with the two TOTAL values. If `total` reports an error, write the error under `## Spending` instead of numbers.

## 4. Write the note

Path, by period:
- Daily: `summaries/daily/YYYY-MM-DD.md` (the date `D`)
- Weekly: `summaries/weekly/YYYY-Www.md` (the week label)
- Monthly: `summaries/monthly/YYYY-MM.md` (the month label)

If the file already exists, replace it with the fresh summary and keep its original `created` date. Summaries are generated notes, so regenerating them is allowed.

Frontmatter:

```yaml
---
type: summary
period: daily | weekly | monthly
start: YYYY-MM-DD
end: YYYY-MM-DD
tags: [summary]
created: YYYY-MM-DD
updated: YYYY-MM-DD
---
```

The title is the first line under the frontmatter:
- Daily: `# Daily summary: Friday 2026-10-02`
- Weekly: `# Weekly summary: Monday 2026-09-28 to Sunday 2026-10-04 (2026-W40)`
- Monthly: `# Monthly summary: October 2026 (Thursday 2026-10-01 to Saturday 2026-10-31)`

Sections, in this order. Keep every heading. Under a heading with nothing to show, write `- None`.

**Daily**
1. `## Overdue`
2. `## Today` — events, birthdays, and tasks due on `D`, sorted by time
3. `## Yesterday` — events, completed tasks, and log highlights from the recap day
4. `## Next 7 days` — upcoming events, birthdays, and tasks due, grouped by day with the weekday
5. `## Open tasks with no due date`
6. `## Inbox`

**Weekly and monthly**
1. `## Overdue`
2. `## Events` — events in the period, grouped by day with the weekday
3. `## Birthdays` — birthdays in the period, with the weekday and age
4. `## Tasks due`
5. `## Tasks completed`
6. `## Log highlights`
7. `## Spending` (monthly only, leave it out of weekly) — the format below
8. `## Next week` (weekly) or `## Next month` (monthly) — upcoming events, birthdays, and tasks due
9. `## Open tasks with no due date`
10. `## Inbox`

The Spending section, with every number copied from the script (add thousands separators for display only): Amounts are in the home currency from settings.md.

    - **Total: 1,284.35 <home>** (47 entries) · [[spending/2026-10|ledger]]
    - Previous month: 1,102.80 <home> (+181.55)
    - By category:
      - groceries: 412.60 (32%)
    - Largest entries:
      - Saturday 2026-10-03: 61.70 shopping "headphones" (45.00 USD)

Link the ledger with its folder, `[[spending/YYYY-MM|ledger]]`, because the monthly summary note has the same file name. Leave out the Previous month line when there is no previous ledger. Show a converted entry's original amount and currency in brackets. With no ledger for the month, write `- None`.

Each item is one bullet: what it is, its date with weekday, and its wikilink. For example:
- `- Monday 2026-10-05: [[2026-10-05-dentist]] at 14:00, Main St Clinic`
- `- Wednesday 2026-10-07: [[jane-doe]] turns 30`
- `- Back up the vault (due: Friday 2026-10-09)`

## 5. Sync and reply

Run `bash scripts/sync.sh "summary: <period> <label>"`, for example `summary: weekly 2026-W40`. Do not add an entry to the daily log for a summary.

Reply with the file path, the period it covers, and whether it was pushed (only after `SYNC OK`). Then give the overdue items and the next few things coming up in 2 to 5 lines, so I do not have to open the note.
