# Settings, `/setup`, and Generic Docs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move time zone, home currency, and About me into a `settings.md` and `about-me.md` that `/setup` writes in the private vault. Block requests until setup is done. Support any Bank of Canada currency as home currency. Make the public docs generic.

**Architecture:**
- `spending.sh` reads `currency` from the vault's `settings.md` frontmatter. It computes cross rates for a non-CAD home currency and gains `check-currency`.
- A new `setup` skill asks, validates, and writes the two notes.
- `AGENTS.md` and the `summary` skill gate on `settings.md`.
- The docs are rewritten for forks.

**Tech Stack:** Bash, `awk` (mawk-compatible), `jq`, `curl`, GNU `date`, Markdown skills.

**Spec:** `specs/2026-10-02-setup-and-settings-design.md`

## Global Constraints

- **Do not run** `scripts/spending.sh` or `scripts/test-spending.sh` here. They run only on the server (`DEPLOY.md` step 10). `scripts/test-sync.sh` may run.
- **Sync:** setup files with `bash scripts/sync.sh --code "type: …"`. The template (`jarvis-vault/`) with `bash scripts/sync.sh "type: …"`, only while `git -C jarvis-vault remote get-url origin` ends in `jarvis-vault-template.git`.
- **Public repository:** the only allowed `mssio` mentions are the upstream `github.com/mssio/jarvis-claude` and the template `github.com/mssio/jarvis-vault-template`. No personal data anywhere outside the private vault.
- **`awk`:** no `{n}` interval braces, no `asort`, no octal escapes. Pass a single quote in with `-v`.
- **Messages:** the error strings below are exact; tests and docs match them.
  - `Jarvis is not set up yet (no settings.md). Run /setup.`
  - `settings.md has no valid currency. Run /setup.`
  - `the amount is already in <HOME>`
  - The gate reply: `Jarvis isn't set up yet. Run /setup to choose your time zone and currency.`
- **README:** at most 100 lines.

## Review Focus

1. **The settings file is edited in Obsidian** and gains quotes (`"CAD"`), a CRLF ending, or a different key order. Values must still read. Tests cover quotes and a missing frontmatter; CRLF is stripped in the reader.
2. **A home currency of CAD must give exactly today's output** (the raw Bank of Canada string, such as `1.3700`), so existing ledgers and docs stay consistent. Checked by inspection in Task 1 step 3; live check in `DEPLOY.md`.
3. **`die` inside `$(…)` only exits the subshell.** Every call that captures `home_currency` or `valet` must be followed by `|| exit 1`. Checked by inspection.
4. **A cron summary with no settings** must stop with a clear message and no commit. Covered by the summary skill text; live check in `DEPLOY.md`.
5. **Existing spending tests on a server without `settings.md`.** Rate tests must not depend on the real vault, so the test file sets `JARVIS_SETTINGS` to a fixture before them.

---

## File map

| File | Status | Responsibility |
|---|---|---|
| `scripts/spending.sh` | Modify | Settings reader, home currency, cross rates, `check-currency` |
| `scripts/test-spending.sh` | Modify | Settings fixtures, 8 new offline cases (35 → 43) |
| `.claude/skills/setup/SKILL.md` | Create | The `/setup` flow |
| `AGENTS.md` | Modify | `## Setup` gate; time zone and currency from settings; `setup` commit type |
| `.claude/skills/summary/SKILL.md` | Modify | The gate; settings-based time zone and currency wording |
| `jarvis-vault/about-me.md` | Delete (template) | `/setup` writes it |
| `jarvis-vault/templates/spending.md` | Modify (template) | `currency:` field, generic header |
| `jarvis-vault/README.md` | Modify (template) | Point to `/setup` |
| `DEPLOY.md` | Rewrite | Generic, for forks, with a `/setup` step |
| `OBSIDIAN.md` | Modify | Placeholder user, settings through Properties |
| `README.md` | Rewrite | Current state, Getting started, a `/setup` section |

---

### Task 1: Home currency in `spending.sh`

**Files:** Modify `scripts/spending.sh`, `scripts/test-spending.sh`

**Interfaces:**
- Consumes: the existing `die`, `cmd_total`, `cmd_convert`, `cmd_delta`.
- Produces:
  - `rate CUR DATE` prints `rate<TAB>YYYY-MM-DD`. For a CAD home this is the raw Bank of Canada string. For any other home it is `%.6f`.
  - `check-currency CUR` prints `ok`.
  - Both read `JARVIS_SETTINGS`, which defaults to `<project>/jarvis-vault/settings.md`.

- [ ] **Step 1: Add the tests**

In `scripts/test-spending.sh`, replace the line `# --- rate (input checks only; they fail before any network call) ---` with:

```bash
# --- settings ---

# settings FILE LINE...: writes a settings note whose frontmatter holds the given lines
settings() {
  local file="$1"
  shift
  { echo '---'; echo 'type: settings'; printf '%s\n' "$@"; echo '---'; echo; echo '# Settings'; } > "$file"
}

settings "$tmp/cad.md" "timezone: America/Edmonton" "currency: CAD"
settings "$tmp/eur.md" "timezone: Europe/Berlin" "currency: EUR"
settings "$tmp/quoted.md" "timezone: UTC" 'currency: "eur"'
settings "$tmp/nocurrency.md" "timezone: UTC"
printf '%s\n' '# Settings' '' 'currency: CAD' > "$tmp/nofrontmatter.md"

# The rate tests below use a CAD home unless they say otherwise.
export JARVIS_SETTINGS="$tmp/cad.md"

expect_error "settings: EUR home refuses EUR" "already in EUR" \
  env JARVIS_SETTINGS="$tmp/eur.md" bash scripts/spending.sh rate EUR 2026-10-01
expect_error "settings: quoted lowercase value is read" "already in EUR" \
  env JARVIS_SETTINGS="$tmp/quoted.md" bash scripts/spending.sh rate EUR 2026-10-01
expect_error "settings: missing file means not set up" "not set up yet" \
  env JARVIS_SETTINGS="$tmp/none.md" bash scripts/spending.sh rate USD 2026-10-01
expect_error "settings: no currency key" "no valid currency" \
  env JARVIS_SETTINGS="$tmp/nocurrency.md" bash scripts/spending.sh rate USD 2026-10-01
expect_error "settings: values outside the frontmatter are ignored" "no valid currency" \
  env JARVIS_SETTINGS="$tmp/nofrontmatter.md" bash scripts/spending.sh rate USD 2026-10-01

# --- check-currency (offline cases only) ---

expect "check-currency: CAD needs no network" "ok" "$(sp check-currency CAD)"
expect_error "check-currency: bad code" "not a currency code" sp check-currency US
expect_error "check-currency: missing code" "usage: check-currency CURRENCY" sp check-currency

# --- rate (input checks only; they fail before any network call) ---
```

The 6 existing rate tests stay below, unchanged. They now run with the CAD fixture. Total: 35 + 8 = 43.

- [ ] **Step 2: Add the settings reader and helpers to `spending.sh`**

Update the header comment's command list:

```bash
#   bash scripts/spending.sh rate CUR DATE         rate from CUR to the home currency for DATE,
#                                                  or the last one published before it
#   bash scripts/spending.sh check-currency CUR    ok if the Bank of Canada publishes CUR
#
# The home currency is "currency" in the vault's settings.md (written by /setup).
# JARVIS_SETTINGS can point to another settings file (the tests use this).
```

Insert after `cents_to_amount() { … }`:

```bash
settings_file() {
  printf '%s' "${JARVIS_SETTINGS:-$(cd "$(dirname "$0")/.." && pwd)/jarvis-vault/settings.md}"
}

# setting KEY FILE: prints KEY's value from FILE's frontmatter, or nothing.
# Trims spaces, drops one pair of surrounding quotes, ignores a CRLF ending.
setting() {
  awk -v key="$1" -v q="'" '
    { sub(/\r$/, "") }
    NR == 1 { if ($0 !~ /^---[ \t]*$/) exit; next }
    /^---[ \t]*$/ { exit }
    index($0, ":") > 0 {
      k = substr($0, 1, index($0, ":") - 1)
      gsub(/^[ \t]+|[ \t]+$/, "", k)
      if (k != key) next
      v = substr($0, index($0, ":") + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      f = substr(v, 1, 1); l = substr(v, length(v), 1)
      if (length(v) >= 2 && f == l && (f == "\"" || f == q)) v = substr(v, 2, length(v) - 2)
      print v
      exit
    }' "$2"
}

home_currency() {
  local file cur
  file="$(settings_file)"
  [ -f "$file" ] || die "Jarvis is not set up yet (no settings.md). Run /setup."
  cur="$(setting currency "$file" | tr '[:lower:]' '[:upper:]')"
  [[ "$cur" =~ ^[A-Z]{3}$ ]] || die "settings.md has no valid currency. Run /setup."
  printf '%s' "$cur"
}

need_tools() {
  command -v curl >/dev/null || die "curl is not installed"
  command -v jq >/dev/null || die "jq is not installed (apt install -y jq)"
}

# valet SERIES START END LABEL: prints the Bank of Canada observations JSON
valet() {
  local url body code
  url="https://www.bankofcanada.ca/valet/observations/$1/json?start_date=$2&end_date=$3"
  if ! body="$(curl -sS --max-time 20 -w '\n%{http_code}' "$url" 2>&1)"; then
    die "could not reach the Bank of Canada: $body"
  fi
  code="${body##*$'\n'}"
  body="${body%$'\n'*}"
  # An unknown series comes back as 404 (or 400 on some API versions).
  case "$code" in
    400|404) die "the Bank of Canada publishes no rate for $4" ;;
  esac
  [ "$code" = "200" ] || die "the Bank of Canada returned HTTP $code"
  printf '%s' "$body"
}
```

- [ ] **Step 3: Replace `cmd_rate` and add `cmd_check_currency`**

Replace the whole `cmd_rate` function with:

```bash
cmd_rate() {
  [ $# -eq 2 ] || die "usage: rate CURRENCY DATE"
  local cur day home start series body result
  cur="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  day="$2"
  [[ "$cur" =~ ^[A-Z]{3}$ ]] || die "not a currency code: $1"
  if ! [[ "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || ! date -d "$day" +%F >/dev/null 2>&1; then
    die "not a date (use YYYY-MM-DD): $day"
  fi
  if [[ "$day" > "$(date +%F)" ]]; then
    die "the date is in the future: $day"
  fi
  home="$(home_currency)" || exit 1
  [ "$cur" != "$home" ] || die "the amount is already in $home"
  need_tools

  # Every Bank of Canada rate is against CAD. For another home currency,
  # rate = (CUR to CAD) / (HOME to CAD), on a day both were published.
  if [ "$home" = "CAD" ]; then
    series="FX${cur}CAD"
  elif [ "$cur" = "CAD" ]; then
    series="FX${home}CAD"
  else
    series="FX${cur}CAD,FX${home}CAD"
  fi

  # Weekends and holidays have no rate, so look back 10 days and take the last one.
  start="$(date -d "$day -10 days" +%F)"
  body="$(valet "$series" "$start" "$day" "$cur")" || exit 1

  result="$(printf '%s' "$body" | jq -r --arg c "FX${cur}CAD" --arg h "FX${home}CAD" '
    def val($s): if $s == "FXCADCAD" then "1" else (.[$s].v // null) end;
    [.observations[]? | {d, c: val($c), h: val($h)} | select(.c != null and .h != null)]
    | sort_by(.d) | last
    | if . == null then empty else "\(.c)\t\(.h)\t\(.d)" end
  ' 2>/dev/null)" || die "could not read the Bank of Canada response"
  [ -n "$result" ] || die "no $cur rate published from $start to $day"

  if [ "$home" = "CAD" ]; then
    # Keep the Bank's own figure, exactly as published.
    printf '%s\n' "$result" | awk -F'\t' '{ printf "%s\t%s\n", $1, $3 }'
  else
    printf '%s\n' "$result" | awk -F'\t' '{ printf "%.6f\t%s\n", $1 / $2, $3 }'
  fi
}

cmd_check_currency() {
  [ $# -eq 1 ] || die "usage: check-currency CURRENCY"
  local cur day start body found
  cur="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  [[ "$cur" =~ ^[A-Z]{3}$ ]] || die "not a currency code: $1"
  if [ "$cur" = "CAD" ]; then
    echo "ok"
    return
  fi
  need_tools
  day="$(date +%F)"
  start="$(date -d "$day -10 days" +%F)"
  body="$(valet "FX${cur}CAD" "$start" "$day" "$cur")" || exit 1
  found="$(printf '%s' "$body" | jq -r --arg s "FX${cur}CAD" \
    '[.observations[]? | select(.[$s].v != null)] | length' 2>/dev/null)" \
    || die "could not read the Bank of Canada response"
  [ "${found:-0}" -gt 0 ] || die "no $cur rate published in the last 10 days"
  echo "ok"
}
```

Replace the `case` block with:

```bash
case "${1:-}" in
  total)          shift; cmd_total "$@" ;;
  convert)        shift; cmd_convert "$@" ;;
  delta)          shift; cmd_delta "$@" ;;
  rate)           shift; cmd_rate "$@" ;;
  check-currency) shift; cmd_check_currency "$@" ;;
  *) die "usage: spending.sh total FILE | convert AMOUNT RATE | delta CURRENT PREVIOUS | rate CURRENCY DATE | check-currency CURRENCY" ;;
esac
```

- [ ] **Step 4: Review by inspection (no run)**

Check each of these by reading the code:
- **CAD home:** with `c = "1.3712"` and `h = "1"`, the output is `1.3712<TAB>date`, identical to the old output.
- **EUR home, CUR = USD:** with `c = 1.3712` and `h = 1.5000`, the output is `0.914133<TAB>date`.
- **EUR home, CUR = CAD:** `c` is `"1"` from `val`, so the output is 1 ÷ 1.5 = `0.666667`.
- **Exits:** every `$(home_currency)` and `$(valet …)` is followed by `|| exit 1`.
- **Order of checks in `rate`:** argument count, then code, then date, then future, then settings, then home equality. So the existing "future date" and "bad date" tests never reach the settings read.
- **The 8 new tests:** trace each one. For example, `nofrontmatter.md` line 1 is `# Settings`, so the reader exits at once and `cur` is empty, which gives "no valid currency".

- [ ] **Step 5: Commit**

Run: `bash scripts/sync.sh --code "chore: home currency from settings, cross rates, check-currency"`
Expected: `SYNC OK: pushed …`

---

### Task 2: The `/setup` skill

**Files:** Create `.claude/skills/setup/SKILL.md`

**Interfaces:**
- Consumes: `spending.sh check-currency`, `sync.sh`.
- Produces: `jarvis-vault/settings.md` and `jarvis-vault/about-me.md` in the shapes below.

- [ ] **Step 1: Write the skill**

````markdown
---
name: setup
description: Set up Jarvis, or change its settings - the time zone, the home currency, and the About me note in the private vault. Use only when the user runs /setup or explicitly asks to set up Jarvis or change one of these settings.
allowed-tools: Read, Glob, Write, Edit, Bash(date *), Bash(timedatectl show *), Bash(bash scripts/sync.sh *), Bash(bash scripts/spending.sh *)
---

# Setup

Creates or updates the two notes Jarvis needs before it does anything else:

- `jarvis-vault/settings.md`: `timezone` and `currency`, read at the start of every request.
- `jarvis-vault/about-me.md`: who I am, what I track, and how I like answers written.

Both live in the private vault, never in the public code repository. Ask one question at a time and wait for each answer. Never guess an answer, and never fill in a value I did not give or confirm.

## 1. Pull

Run `bash scripts/sync.sh --pull`.

## 2. Show what exists

Read `jarvis-vault/settings.md` and `jarvis-vault/about-me.md` if they exist. If either exists, show the current values and ask which to change (time zone, currency, About me, or all). Keep everything I do not change.

## 3. Time zone

1. Run `timedatectl show -p Timezone --value` to get the server's zone. If the command fails, there is no suggestion.
2. Ask: `Which time zone should Jarvis use? The server is set to <zone>. Reply "yes" to use it, or give another, for example Europe/London.`
3. Check the zone with Glob on `/usr/share/zoneinfo/<zone>`. If nothing matches, reply `<zone> is not a time zone name I recognise. Use the Area/City form, for example America/Toronto.` and ask again.

## 4. Currency

1. Ask: `What is your home currency? Spending is recorded in it. Give the 3-letter code, for example CAD, USD, or EUR.`
2. Run `bash scripts/spending.sh check-currency <CODE>`.
   - `ok`: accept it.
   - `SPENDING ERROR: …`: show the error, say that Jarvis converts through Bank of Canada rates so only currencies it publishes work, and ask again.

## 5. About me

Ask these one at a time:
1. `Who are you? One line, for example your role or what you do.`
2. `What do you want Jarvis to keep track of?`
3. `How do you like answers written? For example: short bullet points, dates first.`

## 6. Write the notes

**`jarvis-vault/settings.md`**: keep `created` if the file existed, and set `updated` to today (`date +%F`):

```markdown
---
type: settings
timezone: <zone>
currency: <CODE>
created: <YYYY-MM-DD>
updated: <YYYY-MM-DD>
---

# Settings

Jarvis reads these at the start of every request.

- **timezone**: the time zone of every date and time Jarvis writes. The server clock must be set to it.
- **currency**: your home currency. Spending is recorded in it.

Change them by running `/setup` again, or edit the values above (Obsidian shows them as Properties). After a time zone change, also run the `sudo timedatectl set-timezone …` command that `/setup` prints.
```

**`jarvis-vault/about-me.md`**: 2 to 4 lines built only from my three answers, in my words:

```markdown
---
type: about-me
updated: <YYYY-MM-DD>
---

# About me

<line from answer 1>
<line from answer 2>
<line from answer 3>
```

## 7. Warnings

- **Clock:** if the chosen zone differs from the server's zone in step 3, include this line exactly, and say that dates and times are wrong until it is run:
  `sudo timedatectl set-timezone <zone>`
- **Currency change:** if `currency` changed and any `jarvis-vault/spending/20*.md` ledger exists, say that older months stay in the old currency and nothing is converted.

## 8. Sync and reply

Run `bash scripts/sync.sh "setup: settings and about me"`. Reply only after `SYNC OK`:

```
Saved: time zone <zone>, currency <CODE>, About me (<n> lines).
<clock command and warning, if any>
<currency warning, if any>
Jarvis is ready.
```

If the sync fails, give the exact message and say the notes are written on the server but not yet on GitHub.
````

- [ ] **Step 2: Commit**

Run: `bash scripts/sync.sh --code "chore: add /setup skill"`
Expected: `SYNC OK: pushed …`

---

### Task 3: The gate, in `AGENTS.md` and the summary skill

**Files:** Modify `AGENTS.md`, `.claude/skills/summary/SKILL.md`

- [ ] **Step 1: Add `## Setup` to `AGENTS.md`**

Insert before `## Vault structure`:

```markdown
## Setup (check on every request)

After step 1 of Git sync, read `jarvis-vault/settings.md` and `jarvis-vault/about-me.md`.

If `settings.md` is missing, or its frontmatter has no `timezone` or no 3-letter `currency`, reply only:

`Jarvis isn't set up yet. Run /setup to choose your time zone and currency.`

and do nothing else for that request. The only exceptions are `/setup` itself and questions about how to set up Jarvis.

`settings.md` and `about-me.md` are written by `/setup` (`.claude/skills/setup/SKILL.md`). Use their values wherever these rules mention the time zone, the home currency, or how I like answers written.
```

- [ ] **Step 2: Replace the fixed values**

- Rule 3 of Rules for writing: replace `both in Mountain Time (America/Edmonton). Run `date` to get the current date and time instead of assuming it. The server clock is set to Mountain Time.` with `both in the time zone from `settings.md`. The server clock is set to it, so run `date` to get the current date and time instead of assuming it.`
- Vault structure: replace `one spending ledger per month, in CAD` with `one spending ledger per month, in the home currency`. After the `inbox/` line, add `` - `settings.md`, `about-me.md` : written by `/setup`; read on every request ``.
- Git sync rule 3: after `` `summary`, `` insert `` `setup`, ``.
- Spending section:
  - `All amounts are CAD with two decimals.` becomes `All amounts are in the home currency (`currency` in `settings.md`), with two decimals. When you create a ledger, fill its `currency:` field and the Totals line with that code.`
  - In step 5, the Original column example stays. Replace `= 61.70 CAD` with `= 61.70 <home>`.
  - In the reply and confirmation examples, replace each `CAD` with `<home>`.
  - A rate correction recalculates "the home-currency amount".
- About me section: append `It is written by /setup.`

Then run: `grep -n "Mountain\|CAD" AGENTS.md`
Expected: no output.

- [ ] **Step 3: Gate the summary skill**

In `.claude/skills/summary/SKILL.md`:
- Section `## 1. Pull` becomes:

  ```markdown
  ## 1. Pull and check setup

  Run `bash scripts/sync.sh --pull`. Then read `jarvis-vault/settings.md`. If it is missing, or has no `timezone` or `currency`, reply `Jarvis is not set up yet. Run /setup.` and stop: write no note and do not sync. A scheduled run prints this to its log.
  ```
- In the "Follow `AGENTS.md`" sentence, replace `Mountain Time` with `the time zone from settings.md`.
- In the Spending example, replace `CAD` with `<home>` (2 places), and add the sentence: `Amounts are in the home currency from settings.md.`

Run: `grep -n "Mountain\|CAD" .claude/skills/summary/SKILL.md`
Expected: no output.

- [ ] **Step 4: Commit**

Run: `bash scripts/sync.sh --code "chore: setup gate and settings-based time zone and currency"`
Expected: `SYNC OK: pushed …`

---

### Task 4: Template updates

**Files:** in `jarvis-vault/`: delete `about-me.md`; modify `templates/spending.md` and `README.md`.

- [ ] **Step 1: Confirm this is still the template**

Run: `git -C jarvis-vault remote get-url origin`
Expected: ends in `jarvis-vault-template.git`. If it does not, stop and ask the user. Never push template changes into a private vault.

- [ ] **Step 2: Edit the files**

- Delete `jarvis-vault/about-me.md`.
- `jarvis-vault/templates/spending.md`:
  - Add `currency:` after `month:` in the frontmatter.
  - Change the Totals line to `- **Total: 0.00 XXX** (0 entries)`.
  - Change the header to `| Date | Amount | Category | Description | Original |`.
- `jarvis-vault/README.md`: replace `Start by filling in `about-me.md`.` with `After creating your private vault, run `/setup` in Jarvis: it asks for your time zone, home currency, and a few lines about you, and writes `settings.md` and `about-me.md` here.`

- [ ] **Step 3: Commit to the template**

Run: `bash scripts/sync.sh "chore: template for /setup"`
Expected: `SYNC OK: pushed …`, to `jarvis-vault-template`.

---

### Task 5: Generic `DEPLOY.md`

**Files:** Rewrite `DEPLOY.md`

- [ ] **Step 1: Rewrite it**

Keep the current structure and wording where it is already generic. The changes:

1. **Intro table**, three rows:
   - `mssio/jarvis-claude` (upstream, public): the source of the code.
   - Your fork, `<your-github-user>/jarvis-claude`: what your server pulls; read-only, no key.
   - Your private `jarvis-vault`, created from `mssio/jarvis-vault-template`: read and write, with an SSH deploy key.

   Add one line after the table: replace `<your-github-user>` everywhere with your GitHub username.
2. **Part A, "Make your own copies"** (once, in a browser). Delete all current Part A content.
   - **A1. Fork the code.** Open `https://github.com/mssio/jarvis-claude` and click **Fork**. Forks of public repositories are public, which is fine: the code holds no personal data. Your server pulls from your fork, so nobody else's changes reach it until you choose to sync.
   - **A2. Create your private vault.** Open `https://github.com/mssio/jarvis-vault-template`, then **Use this template** > **Create a new repository** > name `jarvis-vault`, **Private**.
   - **A3 (optional). A computer for editing the rules:**

     ```bash
     git clone https://github.com/<your-github-user>/jarvis-claude.git jarvis
     cd jarvis
     git clone https://github.com/<your-github-user>/jarvis-vault.git jarvis-vault
     ```

     Expected: both clones succeed. Edits to the rules sync with `bash scripts/sync.sh --code "…"`.
3. **Part B** changes:
   - **Step 2:** `sudo timedatectl set-timezone <Area/City>    # for example America/Edmonton`, with "Expected: `date` shows your local time." The package table's last row becomes `tzdata | Time zone data`.
   - **Step 5:** key comment `jarvis-server`. Repository names use `<your-github-user>`. Expected: `Hi <your-github-user>/jarvis-vault! …`.
   - **Step 6:** `user.name "Jarvis Server"`, `user.email "jarvis@localhost"`, and clone URLs with `<your-github-user>`.
   - **New step 9, "Run `/setup`"**, after Remote Control (step 8). The old steps 9 to 11 become 10 to 12. Content:
     - In the Claude app, open the "Jarvis" session that step 8 started, or run `claude` in `~/jarvis` on the server, and send `/setup`.
     - It asks, one at a time: time zone (suggesting the server's), home currency (checked against the Bank of Canada), and three questions for About me.
     - It writes `settings.md` and `about-me.md` in your vault and pushes them.
     - Example exchange as a short table: `yes` / `CAD` / three answers.
     - **Expected:** `Saved: time zone …, currency …, About me (3 lines).` then `Jarvis is ready.`
     - If it prints a `sudo timedatectl set-timezone …` line, run it with sudo.
     - Until `/setup` is done, every request gets `Jarvis isn't set up yet. Run /setup …`.
     - Run `/setup` again any time to change a value.

     Final order: 1 Requirements, 2 Packages and clock, 3 User, 4 Claude Code, 5 SSH key, 6 Clone, 7 Sign in, 8 Remote Control, 9 Run `/setup`, 10 Scheduled summaries, 11 Tests, 12 Updating and troubleshooting.
   - **Cron comment:** `# Jarvis summaries. Times are the server's time zone (step 2).`
   - **Tests step:**
     - `test-spending.sh` expected `43 passed, 0 failed`.
     - Live checks: the existing three rate rows, plus `bash scripts/spending.sh check-currency USD` → `ok`, `check-currency XYZ` → `SPENDING ERROR: the Bank of Canada publishes no rate for XYZ`.
     - The rate rows note they assume a CAD home currency.
     - Phone tests 11 and 12:

       | # | Send this | Expected |
       |---|---|---|
       | 11 | On the server, `mv ~/jarvis/jarvis-vault/settings.md /tmp/`, then send `What do I need to do?` | `Jarvis isn't set up yet. Run /setup …` and nothing else |
       | 12 | `mv /tmp/settings.md ~/jarvis/jarvis-vault/`, then `/setup`, keeping every value | The same values, `Jarvis is ready.` |
   - **Updating:** "To get upstream changes, open your fork on GitHub and click **Sync fork**. Your server picks them up on its next request."
   - **Troubleshooting:**
     - "Mountain Time" becomes "your time zone".
     - Add: **"Jarvis isn't set up yet."** Run `/setup` (step 9).
     - Add: **Times off by whole hours.** The server clock differs from `settings.md`; run the `sudo timedatectl set-timezone` line from `/setup`.

- [ ] **Step 2: Check**

Run: `grep -n "mssio" DEPLOY.md`
Expected: only `mssio/jarvis-claude` (the intro and A1) and `mssio/jarvis-vault-template` (the intro and A2).

Run: `grep -n "Mountain\|homelab\|force\|jarvis-vault-template-local\|\.\./jarvis-vault-template" DEPLOY.md`
Expected: no output.

- [ ] **Step 3: Commit**

Run: `bash scripts/sync.sh --code "doc: generic deployment guide with /setup"`
Expected: `SYNC OK: pushed …`

---

### Task 6: `OBSIDIAN.md` and `README.md`

**Files:** Modify `OBSIDIAN.md`; rewrite `README.md`

- [ ] **Step 1: `OBSIDIAN.md`**

- Replace `https://github.com/mssio/jarvis-vault.git` with `https://github.com/<your-github-user>/jarvis-vault.git`.
- Change desktop step 1's reference to "`DEPLOY.md` step A3".
- Add a section before "Excluded files":

  ```markdown
  ## Settings

  `settings.md` in the vault holds your time zone and home currency, and Obsidian shows them as **Properties** you can edit. Editing there works, but `/setup` checks the values for you. After changing the time zone, run `sudo timedatectl set-timezone <zone>` on the server as well.
  ```

- [ ] **Step 2: Rewrite `README.md` (at most 100 lines)**

Keep the current sections and update them, in this order:
1. `# Jarvis`: the intro as now.
2. **New `## Getting started`**, four numbered lines:
   1. Fork this repository.
   2. Create a private vault from the template.
   3. Follow `DEPLOY.md`.
   4. Run `/setup`.
3. `## How it works`: the diagram and bullets as now. Bullet 1 adds "and checks Jarvis is set up".
4. **New `## /setup`**: 5 to 7 lines.
   - What it asks: time zone, home currency, About me.
   - Where it saves: `jarvis-vault/settings.md` and `about-me.md`, private.
   - That every request waits until it has run.
   - How to change values: run it again, or edit the Properties.
   - That times follow the server clock, which `/setup` helps set.
   - Currencies: any currency the Bank of Canada publishes.
5. `## Guides`: as now.
6. `## Folders`: add rows for `jarvis-vault/settings.md` (`/setup`) and change the `about-me.md` row to say written by `/setup`. Keep at most 13 rows.
7. `## Everyday phrases`:
   - Add a first row: `/setup` → "Asks for your time zone, home currency, and About me, and saves them."
   - Change "Converts to CAD" to "Converts to your home currency".
8. `## Good to know`: as now.
9. `## What was tested`, current state:
   - `test-sync.sh`: 13 of 16 pass on Windows; 16 run on the server.
   - Not tested yet (all in `DEPLOY.md` step 11): the 43 spending tests, Bank of Canada live checks, `/setup` and the gate, summaries and cron, Remote Control, and mobile sync.

- [ ] **Step 3: Check**

Run: `wc -l README.md`
Expected: 100 or fewer.

Run: `grep -n "mssio" README.md OBSIDIAN.md`
Expected: only the template link (README) and `mssio/jarvis-claude` if used as the upstream link.

- [ ] **Step 4: Commit**

Run: `bash scripts/sync.sh --code "doc: README and Obsidian guide for /setup and forks"`
Expected: `SYNC OK: pushed …`

---

### Task 7: Final checks

- [ ] **Step 1: Sync tests still pass (unchanged script)**

Run: `bash scripts/test-sync.sh > "$WS/ts.txt" 2>&1; tail -n 1 "$WS/ts.txt"`
Expected: `13 passed, 0 failed, 3 skipped`.

- [ ] **Step 2: Public-readiness scan**

Run: `grep -rn "mssio" --exclude-dir=.git --exclude-dir=jarvis-vault --exclude-dir=specs .`
Expected: only links to `mssio/jarvis-claude` and `mssio/jarvis-vault-template`.

Search tracked files for words from the old About me and the email domain, typing the words at the prompt only, never into a file.
Expected: no output.

- [ ] **Step 3: Commit if anything changed**

Run: `bash scripts/sync.sh --code "chore: final checks"`
Expected: `SYNC OK: …`
