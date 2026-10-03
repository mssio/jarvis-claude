# Settings, `/setup`, and generic docs: design

Date: 2026-10-02
Status: written for review

## Goal

1. Move the remaining personal defaults (time zone, home currency, About me) out of the public code into the private vault.
2. Add a `/setup` skill that creates them by asking questions, checking each answer as it goes.
3. Block every request until setup is done, so nobody runs Jarvis with missing settings.
4. Support any home currency the Bank of Canada publishes, not only CAD.
5. Make `DEPLOY.md`, `OBSIDIAN.md`, and `README.md` generic for anyone who forks the public repository, and document `/setup` well.

## Decisions

| Topic | Decision |
|---|---|
| Where settings live | `jarvis-vault/settings.md`, in the private vault, so they are backed up and synced to every machine. |
| Format | Markdown with YAML frontmatter, so Obsidian shows the values as editable Properties. Flat `key: value` lines only. |
| Keys (v1) | `timezone` (an IANA name such as `America/Edmonton`) and `currency` (a 3-letter code such as `CAD`). |
| Who writes them | The `/setup` skill. The template ships no `settings.md` and no `about-me.md`. |
| Skill name | `/setup`. `/init` is a built-in Claude Code command. |
| Gate | Before any request, `settings.md` must exist with both keys. Otherwise Claude replies only with the "run `/setup`" message. |
| Time zone | The server clock stays the source of every timestamp. `/setup` stores the zone and, if the clock differs, gives the `sudo timedatectl` command. Claude never runs `TZ=… date`, because that would not match the pre-approved `date` permission. |
| Currency | Any currency with a Bank of Canada series (`FX{CUR}CAD`), plus CAD. |
| How others get the code | Fork `mssio/jarvis-claude`; the server pulls from the fork. |

## 1. `jarvis-vault/settings.md`

```markdown
---
type: settings
timezone: America/Edmonton
currency: CAD
created: 2026-10-02
updated: 2026-10-02
---

# Settings

Jarvis reads these at the start of every request.

- **timezone**: the time zone of every date and time Jarvis writes. The server clock must be set to it.
- **currency**: your home currency. Spending is recorded in it.

Change them by running `/setup` again, or edit the values above (Obsidian shows them as Properties). After a time zone change, also run the `sudo timedatectl set-timezone …` command that `/setup` prints.
```

**Reading rules** (for scripts and agents):
- The frontmatter is the lines between the first line `---` and the next `---`.
- A value is the text after the first `:`, with spaces trimmed and one pair of surrounding `"` or `'` removed.
- `currency` is upper-cased.
- Unknown keys are ignored.

**Valid file:**
- `timezone` is non-empty with no spaces, and `/usr/share/zoneinfo/<timezone>` exists. Single-word zones such as `UTC` are valid. The format is checked on every read; the zoneinfo file is checked by `/setup`.
- `currency` matches `^[A-Z]{3}$`.

## 2. The `/setup` skill (`.claude/skills/setup/SKILL.md`)

**Frontmatter:**
- `name: setup`.
- A description saying it runs only when the user runs `/setup` or asks to set up or change Jarvis settings.
- `allowed-tools`:
  - `Read`, `Glob`, `Write`, `Edit`
  - `Bash(date *)`, `Bash(timedatectl show *)`
  - `Bash(bash scripts/sync.sh *)`, `Bash(bash scripts/spending.sh *)`

**Steps:**
1. Run `bash scripts/sync.sh --pull`.
2. If `settings.md` or `about-me.md` exists, show the current values and ask which to change. Keep the rest.
3. **Time zone.**
   - Suggest the server's zone, from `timedatectl show -p Timezone --value`. Accept the suggestion or another IANA name.
   - Check that `/usr/share/zoneinfo/<zone>` exists, using Glob. If it does not, say so and ask again. Never guess.
4. **Currency.**
   - Ask for a 3-letter code. CAD is always accepted.
   - For any other code, run `bash scripts/spending.sh check-currency CUR`. On an error, show it and ask again.
5. **About me.** Ask three questions, one at a time:
   - who you are
   - what you want to track
   - how you like answers written

   Write `about-me.md`: frontmatter `type: about-me`, then 2 to 4 lines built only from the answers.
6. Write `settings.md` (shape in §1). Keep `created` if the file existed, and set `updated` to today.
7. **Clock check.** If the server zone from step 3 differs from the chosen zone, the reply includes, verbatim:
   `sudo timedatectl set-timezone <zone>`
   with a note that Jarvis's dates are wrong until it is run.
8. **Currency change.** If the currency changed and ledgers already exist, warn that older months stay in the old currency. Nothing is converted.
9. Sync with `bash scripts/sync.sh "setup: …"`, then reply with the saved values, any clock command, and "Jarvis is ready."

## 3. Gate and settings in `AGENTS.md`

A new section, `## Setup`, near the top:
- After the opening `--pull`, read `jarvis-vault/settings.md` and `jarvis-vault/about-me.md`.
- If `settings.md` is missing, or `timezone` or `currency` is missing or invalid, reply only:
  `Jarvis isn't set up yet. Run /setup to choose your time zone and currency.`
  Do nothing else.
- **Exceptions:** `/setup` itself, and questions about how to set up Jarvis.

**Replacements:**
- Rule 3: "both in Mountain Time (America/Edmonton)" becomes "both in the time zone from `settings.md`. The server clock is set to it, so `date` already gives the right time."
- Spending section: every "CAD" becomes "the home currency (`currency` in `settings.md`)".
- Vault structure: add `settings.md` and `about-me.md`.
- Commit types: add `setup`.
- About me: the existing pointer to `about-me.md` stays. "Written by `/setup`" is added.

## 4. Any home currency in `scripts/spending.sh`

**Settings file:** `$root/jarvis-vault/settings.md`, overridable with the environment variable `JARVIS_SETTINGS` (used by the tests).

**New internal function `home_currency`:**
- Reads `currency` per the reading rules in §1.
- If the file is missing: `die "Jarvis is not set up yet (no settings.md). Run /setup."`
- If the value is missing or invalid: `die "settings.md has no valid currency. Run /setup."`

**`rate CUR DATE`:**
- The existing checks stay: argument count, code format, date format, and future date.
- `HOME=$(home_currency)`. `CUR == HOME` → `die "the amount is already in HOME"`.
- **HOME = CAD:** as today, `FX{CUR}CAD`.
- **HOME ≠ CAD:**
  - Fetch the series `FX{HOME}CAD`, plus `FX{CUR}CAD` unless CUR is CAD, in one Valet request (`observations/FXAAACAD,FXBBBCAD/json`).
  - Take the last date in the window where every needed series has a value.
  - Rate = (CUR→CAD) ÷ (HOME→CAD), where CAD→CAD = 1.
  - Print it with 6 decimals: `rate<TAB>date`.
- Errors as now: 400/404 means "publishes no rate", no common date means "no rate published".

**New `check-currency CUR`:**
- Validates the format.
- `CAD` prints `ok` with no network call.
- Otherwise it fetches the last 10 days of `FX{CUR}CAD`. It prints `ok` when there is at least one value, and an error otherwise.
- It does not need `settings.md`. `/setup` uses it.

`total`, `convert`, and `delta` are unchanged and need no settings.

**Ledgers:**
- `templates/spending.md` gains frontmatter `currency:`.
- The header becomes `| Date | Amount | Category | Description | Original |`, and the Totals line reads `- **Total: 0.00 XXX** (0 entries)`.
- Agents fill in the home currency when they create a ledger.
- Existing ledgers with `Amount (CAD)` stay valid, because `total` skips the header row.

## 5. Summary skill

- At the start, run the same gate. If settings are missing, write `Jarvis is not set up yet. Run /setup.` and stop: no note and no sync. In cron this lands in `~/summary-cron.log`.
- "Mountain Time" becomes "the time zone from `settings.md`". Spending amounts use the home currency.

## 6. Template (`jarvis-vault/`, pushed to `jarvis-vault-template`)

- Remove `about-me.md`. `/setup` writes it.
- Update `templates/spending.md` as in §4.
- `README.md`: "After creating your private vault, run `/setup` in Jarvis."

## 7. Documentation

**`.claude/skills/setup/SKILL.md`:** the steps from §2, with exact messages.

**`README.md`** (at most 100 lines), current state:
- What Jarvis is.
- **Getting started**: fork, then use the template, then `DEPLOY.md`, then `/setup`.
- How it works.
- A short **`/setup`** section: what it asks, where it saves, how to re-run it, and that every request waits for it.
- Guides, folders (including `settings.md` and `about-me.md`), everyday phrases (including `/setup`), good to know, and what was tested.

**`DEPLOY.md`**, generic:
- **Intro:** three repositories: the upstream, your fork, and your private vault.
- **Part A, in a browser, once:**
  - A1: fork the code.
  - A2: create a private vault from the template.
  - A3 (optional): set up a computer for editing the rules.
  - No maintainer steps.
- **Part B, steps 1 to 11:**
  - `<your-github-user>`, and `sudo timedatectl set-timezone <Area/City>` with `America/Edmonton` as the example.
  - Neutral names: `Jarvis Server`, `jarvis@localhost`, key comment `jarvis-server`.
  - A new step after sign-in, **Run `/setup`**: what it asks, example answers, the expected reply, the clock command, and how to re-run it.
  - "Server time" wording everywhere.
  - Updating through the **Sync fork** button.
  - Phone tests 11 and 12:
    - 11: rename `settings.md` away, send any request, expect the setup message.
    - 12: rename it back, run `/setup` again, change nothing, expect the same values.
  - New troubleshooting bullets: "Jarvis isn't set up yet", and dates off by hours (the clock command).

**`OBSIDIAN.md`:**
- `<your-github-user>`.
- Mention editing `settings.md` through Properties.

## 8. Testing

**`scripts/test-spending.sh`** (server only, offline). Fixture settings are written in the temporary folder and passed with `JARVIS_SETTINGS`.
- Existing rate tests run with a CAD-home settings fixture, so they still expect "already in CAD".
- New tests:
  - EUR home refuses `EUR`.
  - A quoted `"eur"` value is read as EUR.
  - A missing settings file gives "not set up".
  - Settings with no currency give "no valid currency".
  - `check-currency CAD` prints `ok`.
  - `check-currency US` is a format error.
- **Live server checks** (`DEPLOY.md` step 10):
  - `check-currency USD` gives `ok`; `check-currency XYZ` gives "publishes no rate".
  - With an EUR-home settings file, `rate USD <date>` prints a 6-decimal cross rate.

**`scripts/test-sync.sh`:** unchanged.

**Phone tests 11 and 12:** `/setup` and the gate.

## Out of scope

- More settings keys, such as language or week start. Weeks stay Monday to Sunday.
- Rate sources other than the Bank of Canada.
- Converting old ledgers after a currency change.
