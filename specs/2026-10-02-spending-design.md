# Spending tracking: design

Date: 2026-10-02
Status: approved in conversation, waiting for review of this written spec

## Goal

Track what I spend, so I can see where my money goes each month. I record spending in plain words from my phone, and Jarvis files it. Tracking only: no budgets.

## Decisions

| Topic | Decision |
|---|---|
| Fields | Amount, category, and date. An optional short description. |
| Missing amount or category | Jarvis asks. Nothing is saved until both are known. |
| Missing date | Use today, and say so in the reply. |
| Currency | Everything is stored in CAD. Other currencies are converted before saving, using the Bank of Canada rate. The reply shows the rate. |
| Categories | Start empty. A category that is not on the list needs my confirmation before it is created. |
| Storage | One ledger note per month, with a table of entries. |
| Totals | Recalculated after every add, edit, or delete. |
| Edits and deletes | Always confirmed first. The confirmation shows the entry's date with its weekday. |
| Arithmetic | Done by a script, never by Claude in its head. |
| Report | A Spending section in the monthly summary. Not in daily or weekly summaries. |
| Where it runs | Scripts and tests run only on the homelab container, never in the authoring session. |

## Out of scope

Budgets, income, recurring expenses, charts, storing amounts in other currencies, and spending in daily or weekly summaries.

## 1. Files

All note paths are inside `jarvis-vault/`.

| Path | Purpose |
|---|---|
| `spending/categories.md` | The approved categories, one per line as `- name`, lowercase. Starts with no entries. |
| `spending/YYYY-MM.md` | One ledger per month, named after the month the spending happened (not when it was recorded). Created from the template on the first entry of that month. |
| `templates/spending.md` | The ledger shape below. |

### Ledger shape

```markdown
---
type: spending
month: 2026-10
tags: [spending]
created: 2026-10-02
updated: 2026-10-03
---

# Spending: October 2026

## Totals
- **Total: 76.20 CAD** (2 entries)
- shopping: 61.70 (81%)
- food: 14.50 (19%)

## Entries
| Date | Amount (CAD) | Category | Description | Original |
|---|---|---|---|---|
| 2026-10-02 | 14.50 | food | lunch | |
| 2026-10-03 | 61.70 | shopping | headphones | 45.00 USD × 1.3712 (BoC 2026-10-01) |
```

Row rules:
- Rows are in date order. A new row with the same date as existing rows goes after them.
- `Date` is `YYYY-MM-DD`. `Amount (CAD)` always has exactly two decimals and no thousands separator.
- `Category` is lowercase and must be in `categories.md`.
- `Description` is optional. A `|` in it is replaced with `/` so the table stays intact.
- `Original` is empty for CAD entries. Otherwise it is `AMOUNT CUR × RATE (BoC RATE-DATE)`.
- The Totals section is generated. It is rewritten from the script output after every change and is never edited by hand.

## 2. Recording rules (`AGENTS.md`, new Spending section)

These are vault rules, not a skill, so plain words work without a command.

### Adding

1. **Amount**: required. Ask if missing or unclear.
2. **Category**: required.
   - If missing, ask and list the existing categories.
   - Matching ignores case.
   - If not in `categories.md`, ask: `New category 'snacks'? Existing: food, transport. Yes, or pick one.` Jarvis may suggest a likely existing category, but never picks one by itself. Save nothing until I answer. On yes, add the category to `categories.md`.
3. **Date**: today if not given, and the reply says `(today)`. Relative words such as "yesterday" are worked out with `date`.
4. **Description**: optional, taken from what I said.
5. **Other currency**:
   - Run `bash scripts/spending.sh rate CUR DATE`, then `bash scripts/spending.sh convert AMOUNT RATE`.
   - If the rate cannot be fetched for any reason, including a currency the Bank does not publish, save nothing and ask me for the rate (`What is 1 XYZ in CAD?`). Convert with the rate I give, then confirm the whole entry with its date and weekday before saving. Record it as `(rate given)` in place of `(BoC …)`.
6. Add the row to the right month's ledger, run `bash scripts/spending.sh total FILE`, rewrite Totals from its output, and sync with commit type `spending`.
7. Reply in one line, for example:
   `spending/2026-10.md: 14.50 CAD food "lunch" on Friday 2026-10-02 (today). October total 76.20 CAD. Pushed.`
   A converted entry adds the rate, for example `45.00 USD × 1.3712 (BoC 2026-10-01) = 61.70 CAD`.

### Editing, deleting, and renaming: always confirm first

Every change to an existing row needs my yes first, even when only one row matches. That includes edits, deletes, rate corrections ("use 1.36 instead"), and category renames. The confirmation always shows the date with its weekday:

- `Delete this entry? Friday 2026-10-02 · 14.50 CAD · food · "lunch". Yes / no`
- `Change this entry? Saturday 2026-10-03 · shopping · "headphones": 61.70 → 59.99 CAD. Yes / no`
- `Rename category food → eating out? This changes 12 entries from Thursday 2026-10-01 to Wednesday 2026-10-28 across 1 month. Yes / no`

Rules:
- If more than one row matches, list them, each with its date and weekday, and ask which one.
- A rate correction recalculates the CAD amount with `convert` and updates `Original`.
- After the change: recalculate Totals in every ledger touched, then sync.
- Categories are never removed or renamed without a request. A rename updates `categories.md` and every matching row in every month.

### Other

- **No daily log line** for spending.
- **"Recalculate my spending"**: rerun `total` on the current month's ledger and rewrite Totals. This applies after hand edits.
- **Questions** such as "how much have I spent this month?" are answered from `total` output. Nothing is written.

## 3. Script: `scripts/spending.sh`

Bash and `awk`. `rate` also needs `curl` and `jq`. GNU `date` is assumed, as on Ubuntu.

Output is tab-separated, one record per line, on stdout. Errors go to stderr as `SPENDING ERROR: message` with exit code 1. Success exits 0.

### `total FILE`

Reads the rows in the `## Entries` table. It skips the header and separator rows and ignores everything outside the table.

```
ENTRIES	2
TOTAL	76.20
CATEGORY	shopping	61.70	81
CATEGORY	food	14.50	19
LARGEST	2026-10-03	61.70	shopping	headphones	45.00 USD × 1.3712 (BoC 2026-10-01)
LARGEST	2026-10-02	14.50	food	lunch	
```

- Totals are added in integer cents, so no floating-point drift.
- `CATEGORY` lines are largest first. The last field is the percentage of the total, rounded to a whole number. With a total of 0 there are no `CATEGORY` lines.
- `LARGEST` lists up to 5 rows, largest first. Ties go to the earlier date. The last field is the `Original` column, which is empty for CAD entries.
- A ledger with no rows prints `ENTRIES 0` and `TOTAL 0.00`.
- These are errors, each naming the line number: a row with a bad date, an amount that is not `digits.dd`, or an empty category. A missing file is also an error. A broken ledger never produces a total.

### `convert AMOUNT RATE`

Prints `AMOUNT × RATE` rounded to cents, half up, for example `61.70`. Non-numeric input is an error.

### `delta CURRENT PREVIOUS`

Prints the signed difference, for example `+181.55` or `-12.00`. This is for the monthly summary.

### `rate CUR DATE`

- Fetches `https://www.bankofcanada.ca/valet/observations/FX{CUR}CAD/json` for the 10 days up to and including `DATE`, and prints the last observation: `1.3712	2026-10-01`.
- These are errors:
  - `CUR` is `CAD`
  - the Bank has no series for `CUR`
  - no observation in the window
  - a network failure
  - a date in the future

## 4. Monthly summary (`.claude/skills/summary/SKILL.md`)

Add `## Spending` to the monthly summary, before `## Next month`:

```markdown
## Spending
- **Total: 1,284.35 CAD** (47 entries) · [[2026-10]]
- Previous month: 1,102.80 CAD (+181.55)
- By category:
  - groceries: 412.60 (32%)
- Largest entries:
  - Saturday 2026-10-03: 61.70 shopping "headphones" (45.00 USD)
```

- Every number comes from `total` and `delta`, run on the ledger rows. The stored Totals section is never used.
- The thousands separator is added only for display here.
- The previous month line appears only if that ledger exists.
- No ledger for the month means `- None`.
- Add `Bash(bash scripts/spending.sh *)` to the skill's `allowed-tools`.

## 5. Other changes

- **`AGENTS.md`**:
  - add `spending/` to Vault structure
  - add `spending` to the commit types
  - add the Spending section from part 2
- **`.claude/settings.json`**: allow `Bash(bash scripts/spending.sh *)`. Scheduled runs need this, because they have nobody to approve a prompt.
- **`.obsidian/app.json`**: exclude `specs/` (this folder).
- **README**:
  - add `jq` to the install line in Part 2
  - add `spending/`, `spending.sh`, and `specs/` to the folder table
  - add spending phrases to Everyday phrases
  - add a Part 4 test for adding an entry, a new category, and a USD entry
  - add a step to run the tests on the homelab
  - add the spending items to What was tested

## 6. Testing

Nothing runs in the authoring session. All checks run on the homelab after deploying.

- **`scripts/test-spending.sh`**: offline tests, run with `bash scripts/test-spending.sh`. It prints `PASS` or `FAIL` per case and exits non-zero if any fail. Its fixture ledgers are created in a temporary folder and deleted afterwards.
  - `total`:
    - normal ledger, category order and percentages, `LARGEST` order and ties
    - empty ledger
    - missing file
    - bad date, bad amount, and empty category, each reporting the right line
    - text outside the table ignored
    - many small amounts summing exactly, e.g. 0.10 × 30 = 3.00
  - `convert`: `45.00 1.3712` → `61.70`, `10.00 1.23456` → `12.35`, `0.01 0.5` → `0.01`, non-numeric input → error.
  - `delta`: positive, negative, and zero.
- **Manual live check**: `bash scripts/spending.sh rate USD <recent weekday>` prints a plausible rate and date. Also try one weekend date, and one unknown currency, which should error.
- **From the phone**: the Part 4 tests in the README.

Until these pass on the homelab, the feature is untested and the README says so.
