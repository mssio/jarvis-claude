# Spending Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user record spending in plain words. Jarvis files it in a monthly CAD ledger with exact, script-calculated totals, and the monthly summary reports it.

**Architecture:** Recording rules live in `AGENTS.md`, so no command is needed. A bash and `awk` script, `scripts/spending.sh`, does all arithmetic and fetches Bank of Canada rates; it reads and calculates only, and never writes notes. The existing `summary` skill gains a Spending section that calls the script.

**Tech Stack:** Bash, `awk` (must work with both `mawk` and `gawk`), GNU `date`, `sort`, `curl`, `jq`, Markdown notes.

**Spec:** `specs/2026-10-02-spending-design.md`

## Global Constraints

- **Nothing runs in the authoring session.** Do not execute `scripts/spending.sh` or `scripts/test-spending.sh` while implementing. Write them carefully by inspection. Every run, test, and live check happens in Task 7 on the homelab container.
- **Commits:** all syncing goes through `bash scripts/sync.sh "type: summary"`. Never run `git add`, `git commit`, `git pull`, or `git push` directly (`AGENTS.md`).
- **Amounts:** stored in CAD only, with exactly two decimals and no thousands separator.
- **Arithmetic:** done by `scripts/spending.sh`, never by Claude in its head.
- **Script output:** tab-separated on stdout. Errors: `SPENDING ERROR: message` on stderr, exit 1.
- **awk:** no regex interval braces such as `{4}`, and no `asort`. Ubuntu's default `awk` is `mawk`.
- **Locale:** the script runs with `LC_ALL=C`, so sorting and byte handling are predictable.
- **Note paths** are inside `jarvis-vault/`. Setup files (`scripts/`, `.claude/`, `AGENTS.md`, `README.md`, `specs/`) are at the project root.
- **Rate source:** `https://www.bankofcanada.ca/valet/observations/FX{CUR}CAD/json`, 10-day window up to and including the date.
- **Confirmations:** every edit, delete, rate correction, and category rename is confirmed first, and the confirmation shows the date with its weekday.

## Review Focus

1. **A ledger saved with Windows line endings (CRLF)** gives exactly the same totals as LF. Test in Task 1.
2. **A hand-typed category in different case** ("Food" and "food") is counted as one lowercase category. Test in Task 1.
3. **A hand-typed amount like `14.5` or `1,284.35`** stops with an error naming the line. It must never be silently miscounted. Test in Task 1.
4. **A hand-edited row with no spaces or missing trailing columns** (`|2026-10-06|1.00|food|`) is still read. Test in Task 1.
5. **A weekend or holiday date** gets the last published business-day rate, not an error. Live check in Task 7.

---

## File map

| File | Status | Responsibility |
|---|---|---|
| `scripts/spending.sh` | Create | `total`, `convert`, `delta`, `rate`. Reads and calculates only. |
| `scripts/test-spending.sh` | Create | Offline tests for the script. Prints PASS or FAIL, exits 1 on any failure. |
| `jarvis-vault/templates/spending.md` | Create | Shape of a monthly ledger. |
| `jarvis-vault/spending/categories.md` | Create | Approved categories list, starting empty. |
| `AGENTS.md` | Modify | Spending rules, vault structure, commit type. |
| `.claude/settings.json` | Modify | Allow `bash scripts/spending.sh *`. |
| `.claude/skills/summary/SKILL.md` | Modify | Monthly `## Spending` section. |
| `README.md` | Modify | `jq` install, folder table, phrases, tests, what was tested. |

---

### Task 1: `spending.sh total` and its tests

**Files:**
- Create: `scripts/spending.sh`
- Create: `scripts/test-spending.sh`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `bash scripts/spending.sh total FILE`, printing:
    - `ENTRIES<TAB>n`
    - `TOTAL<TAB>x.xx`
    - zero or more `CATEGORY<TAB>name<TAB>x.xx<TAB>pct` lines, largest first, then by name; none when the total is 0
    - up to 5 `LARGEST<TAB>date<TAB>x.xx<TAB>category<TAB>description<TAB>original` lines, largest first, ties by earlier date, then by row order
  - In `test-spending.sh`: helpers `expect NAME EXPECTED ACTUAL`, `expect_error NAME TEXT COMMAND...`, `ledger FILE` (rows on stdin, first row lands on line 14), `sp` (runs the script), and a `# --- results ---` marker. Later tasks insert their tests above that marker.

- [ ] **Step 1: Write the test file with the `total` tests**

Create `scripts/test-spending.sh`:

```bash
#!/usr/bin/env bash
# Offline tests for scripts/spending.sh. Run on the homelab, from the project folder:
#
#   bash scripts/test-spending.sh
#
# Prints PASS or FAIL for each case and exits 1 if any case fails.
# Fixture ledgers are written to a temporary folder and deleted afterwards.

set -u
cd "$(dirname "$0")/.." || exit 1

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0

sp() { bash scripts/spending.sh "$@"; }

# expect NAME EXPECTED ACTUAL
expect() {
  if [ "$2" = "$3" ]; then
    echo "PASS $1"
    pass=$((pass + 1))
  else
    echo "FAIL $1"
    printf '  expected: %q\n  actual:   %q\n' "$2" "$3"
    fail=$((fail + 1))
  fi
}

# expect_error NAME TEXT COMMAND...
# Passes when COMMAND exits 1 and its stderr contains TEXT.
expect_error() {
  local name="$1" text="$2" out code
  shift 2
  out="$("$@" 2>&1 >/dev/null)"
  code=$?
  if [ "$code" -eq 1 ] && [[ "$out" == *"$text"* ]]; then
    echo "PASS $name"
    pass=$((pass + 1))
  else
    echo "FAIL $name"
    printf '  expected exit 1 with: %s\n  got exit %s: %s\n' "$text" "$code" "$out"
    fail=$((fail + 1))
  fi
}

# ledger FILE: writes a ledger header (13 lines), then the rows from stdin.
# The first row is line 14 of the file.
ledger() {
  {
    printf '%s\n' '---' 'type: spending' 'month: 2026-10' '---' '' \
      '# Spending: October 2026' '' '## Totals' '- **Total: 999.99 CAD** (9 entries)' '' \
      '## Entries' '| Date | Amount (CAD) | Category | Description | Original |' '|---|---|---|---|---|'
    cat
  } > "$1"
}

# --- total ---

ledger "$tmp/normal.md" <<'EOF'
| 2026-10-02 | 14.50 | food | lunch | |
| 2026-10-03 | 61.70 | shopping | headphones | 45.00 USD × 1.3712 (BoC 2026-10-01) |
| 2026-10-05 | 14.50 | transport | bus pass top-up | |
| 2026-10-04 | 9.30 | food | coffee | |

## Notes
| 2026-01-01 | 500.00 | junk | outside the Entries table | |
EOF
normal_expected=$'ENTRIES\t4\nTOTAL\t100.00\nCATEGORY\tshopping\t61.70\t62\nCATEGORY\tfood\t23.80\t24\nCATEGORY\ttransport\t14.50\t15\nLARGEST\t2026-10-03\t61.70\tshopping\theadphones\t45.00 USD × 1.3712 (BoC 2026-10-01)\nLARGEST\t2026-10-02\t14.50\tfood\tlunch\t\nLARGEST\t2026-10-05\t14.50\ttransport\tbus pass top-up\t\nLARGEST\t2026-10-04\t9.30\tfood\tcoffee\t'
expect "total: normal ledger, order, percentages, ties, text outside the table ignored" \
  "$normal_expected" "$(sp total "$tmp/normal.md")"

sed 's/$/\r/' "$tmp/normal.md" > "$tmp/crlf.md"
expect "total: CRLF line endings give the same result" \
  "$normal_expected" "$(sp total "$tmp/crlf.md")"

ledger "$tmp/empty.md" < /dev/null
expect "total: empty ledger" $'ENTRIES\t0\nTOTAL\t0.00' "$(sp total "$tmp/empty.md")"

for i in $(seq 1 30); do echo "| 2026-10-01 | 0.10 | food | item $i | |"; done | ledger "$tmp/small.md"
expect "total: 30 x 0.10 is exactly 3.00" $'TOTAL\t3.00' "$(sp total "$tmp/small.md" | grep '^TOTAL')"
expect "total: at most 5 LARGEST lines" "5" "$(sp total "$tmp/small.md" | grep -c '^LARGEST')"
expect "total: equal rows keep row order" "item 1" "$(sp total "$tmp/small.md" | grep -m1 '^LARGEST' | cut -f5)"

ledger "$tmp/case.md" <<'EOF'
| 2026-10-02 | 10.00 | Food | a | |
| 2026-10-03 | 5.00 | food | b | |
EOF
expect "total: category case is merged" $'CATEGORY\tfood\t15.00\t100' "$(sp total "$tmp/case.md" | grep '^CATEGORY')"

ledger "$tmp/loose.md" <<'EOF'
|2026-10-06|1.00|food|x|
| 2026-10-07 | 2.00 | food |
EOF
expect "total: rows without spaces or trailing columns" $'ENTRIES\t2\nTOTAL\t3.00' "$(sp total "$tmp/loose.md" | head -n 2)"

ledger "$tmp/zero.md" <<'EOF'
| 2026-10-02 | 0.00 | food | free sample | |
EOF
expect "total: zero total has no CATEGORY lines" "0" "$(sp total "$tmp/zero.md" | grep -c '^CATEGORY')"

ledger "$tmp/baddate.md" <<'EOF'
| 2026-10-02 | 14.50 | food | lunch | |
| 10/02/2026 | 1.00 | food | x | |
EOF
expect_error "total: bad date names its line" "line 15: bad date" sp total "$tmp/baddate.md"

ledger "$tmp/badamount.md" <<'EOF'
| 2026-10-02 | 14.5 | food | lunch | |
EOF
expect_error "total: one-decimal amount names its line" "line 14: bad amount" sp total "$tmp/badamount.md"

ledger "$tmp/comma.md" <<'EOF'
| 2026-10-02 | 1,284.35 | food | lunch | |
EOF
expect_error "total: thousands separator names its line" "line 14: bad amount" sp total "$tmp/comma.md"

ledger "$tmp/nocat.md" <<'EOF'
| 2026-10-02 | 14.50 |  | lunch | |
EOF
expect_error "total: empty category names its line" "line 14: empty category" sp total "$tmp/nocat.md"

expect_error "total: missing file" "no such file" sp total "$tmp/does-not-exist.md"
expect_error "total: no file given" "usage: total FILE" sp total

# --- results ---

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Write `scripts/spending.sh` with `total`**

Create `scripts/spending.sh`:

```bash
#!/usr/bin/env bash
# Spending arithmetic for the Jarvis vault. It only reads and calculates; it never writes notes.
#
#   bash scripts/spending.sh total FILE            totals for one month's ledger
#   bash scripts/spending.sh convert AMOUNT RATE   AMOUNT x RATE, rounded to cents (half up)
#   bash scripts/spending.sh delta CURRENT PREV    signed difference, for example +181.55
#   bash scripts/spending.sh rate CUR DATE         Bank of Canada CUR to CAD rate for DATE,
#                                                  or the last one published before it
#
# Output is tab-separated on stdout. On any problem it prints
# "SPENDING ERROR: message" on stderr and exits 1.

set -u
export LC_ALL=C
TAB="$(printf '\t')"

die() {
  echo "SPENDING ERROR: $1" >&2
  exit 1
}

is_number() {
  [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]
}

cents_to_amount() {
  printf '%d.%02d' $(($1 / 100)) $(($1 % 100))
}

cmd_total() {
  [ $# -eq 1 ] || die "usage: total FILE"
  local file="$1" raw status n total
  [ -f "$file" ] || die "no such file: $file"

  # Reads the rows of the "## Entries" table. Prints one R line per row,
  # one N line with the count and total in cents, and one C line per category.
  # On a bad row it prints an ERR line and exits 3.
  raw="$(awk -F'|' '
    function trim(s) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", s); return s }
    function fail(msg) { print "ERR\t" msg; failed = 1; exit 3 }
    { sub(/\r$/, "") }
    /^## / { in_entries = ($0 ~ /^## Entries[ \t]*$/); next }
    !in_entries { next }
    $0 !~ /^[ \t]*\|/ { next }
    {
      date = trim($2); amount = trim($3); cat = tolower(trim($4))
      desc = trim($5); orig = trim($6)
      if (date == "Date") next
      if (date ~ /^:?-+:?$/) next
      if (date !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) fail("line " NR ": bad date \"" date "\"")
      if (amount !~ /^[0-9]+\.[0-9][0-9]$/) fail("line " NR ": bad amount \"" amount "\" (use digits with two decimals, for example 14.50)")
      if (cat == "") fail("line " NR ": empty category")
      split(amount, p, ".")
      cents = p[1] * 100 + p[2]
      n++
      total += cents
      bycat[cat] += cents
      printf "R\t%d\t%s\t%d\t%s\t%s\t%s\n", cents, date, n, cat, desc, orig
    }
    END {
      if (failed) exit 3
      printf "N\t%d\t%d\n", n, total
      for (c in bycat) printf "C\t%d\t%s\n", bycat[c], c
    }
  ' "$file")"
  status=$?
  if [ "$status" -eq 3 ]; then
    die "$file: $(printf '%s\n' "$raw" | grep '^ERR' | cut -f2-)"
  fi
  [ "$status" -eq 0 ] || die "could not read $file"

  n="$(printf '%s\n' "$raw" | awk -F'\t' '$1 == "N" { print $2 }')"
  total="$(printf '%s\n' "$raw" | awk -F'\t' '$1 == "N" { print $3 }')"
  printf 'ENTRIES\t%s\n' "$n"
  printf 'TOTAL\t%s\n' "$(cents_to_amount "$total")"

  # Categories: largest first, then by name. Percentages are rounded half up.
  if [ "$total" -gt 0 ]; then
    printf '%s\n' "$raw" | awk -F'\t' '$1 == "C"' | sort -t "$TAB" -k2,2nr -k3,3 \
      | awk -F'\t' -v total="$total" '{
          printf "CATEGORY\t%s\t%d.%02d\t%d\n", $3, int($2 / 100), $2 % 100, int($2 * 100 / total + 0.5)
        }'
  fi

  # Largest 5 rows: by amount, then earlier date, then row order.
  printf '%s\n' "$raw" | awk -F'\t' '$1 == "R"' | sort -t "$TAB" -k2,2nr -k3,3 -k4,4n | head -n 5 \
    | awk -F'\t' '{
        printf "LARGEST\t%s\t%d.%02d\t%s\t%s\t%s\n", $3, int($2 / 100), $2 % 100, $5, $6, $7
      }'
}

case "${1:-}" in
  total) shift; cmd_total "$@" ;;
  *) die "usage: spending.sh total FILE" ;;
esac
```

- [ ] **Step 3: Review by inspection (no run)**

Trace `normal.md` through the script by hand and confirm it gives `normal_expected`:
- The rows sum to 1450 + 6170 + 1450 + 930 = 10000 cents = 100.00.
- Categories: shopping 6170 (62%), food 2380 (24%), transport 1450 (14.5 rounds half up to 15).
- LARGEST: 61.70, then the two 14.50 rows (2026-10-02 before 2026-10-05), then 9.30.
- The `## Notes` row comes after a new `## ` heading, so `in_entries` is 0 and the row is skipped.
- The `## Totals` line starts with `-`, so it is skipped.

Confirm there are no `{n}` regex braces and no `asort`.

- [ ] **Step 4: Commit**

Run: `bash scripts/sync.sh "chore: add spending total script and tests"`
Expected: `SYNC OK: pushed …`

---

### Task 2: `convert` and `delta`

**Files:**
- Modify: `scripts/spending.sh` (add two functions, extend the `case`)
- Modify: `scripts/test-spending.sh` (insert tests above `# --- results ---`)

**Interfaces:**
- Consumes: `die`, `is_number` from Task 1.
- Produces:
  - `bash scripts/spending.sh convert AMOUNT RATE` prints `x.xx`, rounded half up.
  - `bash scripts/spending.sh delta CURRENT PREVIOUS` prints `+x.xx`, `-x.xx`, or `0.00`.

- [ ] **Step 1: Add the tests**

Insert above `# --- results ---` in `scripts/test-spending.sh`:

```bash
# --- convert ---

expect "convert: 45.00 x 1.3712" "61.70" "$(sp convert 45.00 1.3712)"
expect "convert: 10.00 x 1.23456 rounds up" "12.35" "$(sp convert 10.00 1.23456)"
expect "convert: exact half cent rounds up" "0.01" "$(sp convert 0.01 0.5)"
expect "convert: whole numbers" "100.00" "$(sp convert 100 1)"
expect_error "convert: amount not a number" "amount is not a number" sp convert abc 1.2
expect_error "convert: rate not a number" "rate is not a number" sp convert 10 x
expect_error "convert: missing rate" "usage: convert AMOUNT RATE" sp convert 10

# --- delta ---

expect "delta: increase" "+181.55" "$(sp delta 1284.35 1102.80)"
expect "delta: decrease" "-12.00" "$(sp delta 10.00 22.00)"
expect "delta: no change" "0.00" "$(sp delta 5.00 5.00)"
expect_error "delta: not a number" "not a number" sp delta 1,284.35 10
expect_error "delta: missing value" "usage: delta CURRENT PREVIOUS" sp delta 10
```

- [ ] **Step 2: Add the functions**

Insert in `scripts/spending.sh`, after `cmd_total` and before the `case`:

```bash
cmd_convert() {
  [ $# -eq 2 ] || die "usage: convert AMOUNT RATE"
  is_number "$1" || die "amount is not a number: $1"
  is_number "$2" || die "rate is not a number: $2"
  # The tiny epsilon keeps exact half cents (0.005) from rounding down through float error.
  awk -v a="$1" -v r="$2" 'BEGIN {
    c = int(a * r * 100 + 0.5 + 1e-9)
    printf "%d.%02d\n", int(c / 100), c % 100
  }'
}

cmd_delta() {
  [ $# -eq 2 ] || die "usage: delta CURRENT PREVIOUS"
  is_number "$1" || die "not a number: $1"
  is_number "$2" || die "not a number: $2"
  awk -v a="$1" -v b="$2" 'BEGIN {
    d = int(a * 100 + 0.5) - int(b * 100 + 0.5)
    sign = ""
    if (d > 0) sign = "+"
    if (d < 0) { sign = "-"; d = -d }
    printf "%s%d.%02d\n", sign, int(d / 100), d % 100
  }'
}
```

Replace the `case` block with:

```bash
case "${1:-}" in
  total)   shift; cmd_total "$@" ;;
  convert) shift; cmd_convert "$@" ;;
  delta)   shift; cmd_delta "$@" ;;
  *) die "usage: spending.sh total FILE | convert AMOUNT RATE | delta CURRENT PREVIOUS" ;;
esac
```

- [ ] **Step 3: Review by inspection (no run)**

Check by hand:
- 45 × 1.3712 = 61.704 → 6170.4 + 0.5 → 6170 → `61.70`.
- 10 × 1.23456 = 12.3456 → 1235.06 → `12.35`.
- 0.01 × 0.5 × 100 = 0.5, + 0.5 → 1 → `0.01`.
- 1284.35 → 128435, 1102.80 → 110280, difference 18155 → `+181.55`.

- [ ] **Step 4: Commit**

Run: `bash scripts/sync.sh "chore: add spending convert and delta"`
Expected: `SYNC OK: pushed …`

---

### Task 3: `rate` (Bank of Canada)

**Files:**
- Modify: `scripts/spending.sh` (add `cmd_rate`, extend the `case`)
- Modify: `scripts/test-spending.sh` (insert offline validation tests above `# --- results ---`)

**Interfaces:**
- Consumes: `die` from Task 1.
- Produces: `bash scripts/spending.sh rate CUR DATE` prints `rate<TAB>YYYY-MM-DD`, the last observation from DATE minus 10 days through DATE.

- [ ] **Step 1: Add the offline tests**

Every check here fails before any network call, so the test file stays offline. Insert above `# --- results ---`:

```bash
# --- rate (input checks only; they fail before any network call) ---

expect_error "rate: CAD is refused" "already in CAD" sp rate CAD 2026-10-01
expect_error "rate: lowercase cad is refused" "already in CAD" sp rate cad 2026-10-01
expect_error "rate: future date" "in the future" sp rate USD 2999-01-01
expect_error "rate: bad date" "not a date" sp rate USD 10/02/2026
expect_error "rate: bad currency code" "not a currency code" sp rate US 2026-10-01
expect_error "rate: missing date" "usage: rate CURRENCY DATE" sp rate USD
```

- [ ] **Step 2: Add the function**

Insert in `scripts/spending.sh`, after `cmd_delta` and before the `case`:

```bash
cmd_rate() {
  [ $# -eq 2 ] || die "usage: rate CURRENCY DATE"
  local cur day start url body code result
  cur="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  day="$2"
  [[ "$cur" =~ ^[A-Z]{3}$ ]] || die "not a currency code: $1"
  [ "$cur" != "CAD" ] || die "the amount is already in CAD"
  if ! [[ "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || ! date -d "$day" +%F >/dev/null 2>&1; then
    die "not a date (use YYYY-MM-DD): $day"
  fi
  if [[ "$day" > "$(date +%F)" ]]; then
    die "the date is in the future: $day"
  fi
  command -v curl >/dev/null || die "curl is not installed"
  command -v jq >/dev/null || die "jq is not installed (apt install -y jq)"

  # Weekends and holidays have no rate, so look back 10 days and take the last one.
  start="$(date -d "$day -10 days" +%F)"
  url="https://www.bankofcanada.ca/valet/observations/FX${cur}CAD/json?start_date=${start}&end_date=${day}"
  if ! body="$(curl -sS --max-time 20 -w '\n%{http_code}' "$url" 2>&1)"; then
    die "could not reach the Bank of Canada: $body"
  fi
  code="${body##*$'\n'}"
  body="${body%$'\n'*}"
  [ "$code" != "404" ] || die "the Bank of Canada publishes no rate for $cur"
  [ "$code" = "200" ] || die "the Bank of Canada returned HTTP $code"

  result="$(printf '%s' "$body" | jq -r --arg s "FX${cur}CAD" '
    [.observations[]? | select(.[$s].v != null) | {d, v: .[$s].v}]
    | sort_by(.d) | last
    | if . == null then empty else "\(.v)\t\(.d)" end
  ' 2>/dev/null)" || die "could not read the Bank of Canada response"
  [ -n "$result" ] || die "no $cur rate published from $start to $day"
  printf '%s\n' "$result"
}
```

Replace the `case` block with:

```bash
case "${1:-}" in
  total)   shift; cmd_total "$@" ;;
  convert) shift; cmd_convert "$@" ;;
  delta)   shift; cmd_delta "$@" ;;
  rate)    shift; cmd_rate "$@" ;;
  *) die "usage: spending.sh total FILE | convert AMOUNT RATE | delta CURRENT PREVIOUS | rate CURRENCY DATE" ;;
esac
```

- [ ] **Step 3: Review by inspection (no run)**

Confirm:
- The order of checks is: argument count, currency code, CAD, date format, future date, then tools, then network. All six offline tests fail before `curl`.
- `[[ "$day" > ... ]]` is a string comparison, which is correct for `YYYY-MM-DD`.
- Bash `[[ =~ ]]` supports `{3}` and `{4}`. The no-braces rule applies to `awk` only.

- [ ] **Step 4: Commit**

Run: `bash scripts/sync.sh "chore: add spending rate lookup"`
Expected: `SYNC OK: pushed …`

---

### Task 4: Vault rules, template, categories, and permission

**Files:**
- Create: `jarvis-vault/templates/spending.md`
- Create: `jarvis-vault/spending/categories.md`
- Modify: `AGENTS.md` (commit types line 13; Vault structure after the `inbox/` line; new section before `## Rules for answering`)
- Modify: `.claude/settings.json` (`permissions.allow`)

**Interfaces:**
- Consumes: the four script commands and their output formats from Tasks 1 to 3.
- Produces:
  - ledger notes at `jarvis-vault/spending/YYYY-MM.md`, in the template shape
  - `jarvis-vault/spending/categories.md` with lines `- name`
  - commit type `spending`

- [ ] **Step 1: Create the template**

`jarvis-vault/templates/spending.md`:

```markdown
---
type: spending
month:
tags: [spending]
created:
updated:
---

# Spending:

## Totals
- **Total: 0.00 CAD** (0 entries)

## Entries
| Date | Amount (CAD) | Category | Description | Original |
|---|---|---|---|---|
```

- [ ] **Step 2: Create the categories list**

`jarvis-vault/spending/categories.md`:

```markdown
---
type: spending-categories
tags: [spending]
created: 2026-10-02
updated: 2026-10-02
---

# Spending categories

Approved categories, one per line as `- name`, lowercase. Jarvis adds one only after you confirm it.

```

- [ ] **Step 3: Add the commit type and the vault structure line in `AGENTS.md`**

In Git sync rule 3, change `` `inbox`, `summary`, `chore`. `` to `` `inbox`, `summary`, `spending`, `chore`. ``

After the line ``- `inbox/` : anything you are unsure where to file``, add:

```markdown
- `spending/YYYY-MM.md` : one spending ledger per month, in CAD; `spending/categories.md` : the approved spending categories
```

- [ ] **Step 4: Add the Spending section to `AGENTS.md`**

Insert before `## Rules for answering`:

````markdown
## Spending

Ledgers are `spending/YYYY-MM.md`, one per month, named after the month the spending happened (not when I told you). Create a missing one from `templates/spending.md`. All amounts are CAD with two decimals. Never do the arithmetic yourself: use `bash scripts/spending.sh`, and copy its numbers exactly.

**Adding**, for example "spent 14.50 on lunch, food":
1. Amount: required. Ask if missing or unclear.
2. Category: required. If missing, ask and list the categories in `spending/categories.md`. Match ignoring case and store lowercase. If it is not on the list, ask `New category 'snacks'? Existing: food, transport. Yes, or pick one.` and save nothing until I answer. You may suggest a likely existing category, but never pick one yourself. On yes, add `- snacks` to `spending/categories.md`.
3. Date: today if I gave none, and say `(today)` in the reply. Work out "yesterday", "last Friday", and so on with `date`.
4. Description: optional, from what I said. Replace any `|` with `/`.
5. Another currency: run `bash scripts/spending.sh rate CUR DATE`, then `bash scripts/spending.sh convert AMOUNT RATE`. Put `AMOUNT CUR × RATE (BoC RATE-DATE)` in the Original column. If `rate` fails, save nothing, tell me the error, and ask for a rate. A rate I give is recorded as `(rate given)` in place of `(BoC …)`.
6. Add the row in date order (after rows with the same date). Run `bash scripts/spending.sh total spending/YYYY-MM.md` (with the `jarvis-vault/` prefix), and rewrite the `## Totals` section from its output: `- **Total: X CAD** (N entries)`, then one `- category: amount (pct%)` line per CATEGORY line.
7. Sync with type `spending`, then reply in one line, for example `spending/2026-10.md: 14.50 CAD food "lunch" on Friday 2026-10-02 (today). October total 76.20 CAD. Pushed.` For a converted entry, add the rate, for example `45.00 USD × 1.3712 (BoC 2026-10-01) = 61.70 CAD`.

**Editing, deleting, rate corrections, and category renames: always ask first.** Every change to an existing row needs my yes, even when only one row matches. The question always shows the date with its weekday, for example:
- `Delete this entry? Friday 2026-10-02 · 14.50 CAD · food · "lunch". Yes / no`
- `Change this entry? Saturday 2026-10-03 · shopping · "headphones": 61.70 → 59.99 CAD. Yes / no`
- `Rename category food → eating out? This changes 12 entries from Thursday 2026-10-01 to Wednesday 2026-10-28 across 1 month. Yes / no`

If more than one row matches, list them with their dates and weekdays and ask which one. A rate correction recalculates the CAD amount with `convert` and updates Original. After the change, recalculate Totals in every ledger touched, then sync. Never remove or rename a category unless I ask. A rename updates `spending/categories.md` and every matching row in every month.

**Other:**
- Do not add spending to the daily log.
- "Recalculate my spending": rerun `total` on the current month's ledger and rewrite Totals. Use this after I edit a ledger by hand.
- Questions like "how much have I spent this month?" are answered from `total` output. Nothing is written.
- If `total` reports a bad row, tell me the line and do not change anything until it is fixed.
````

- [ ] **Step 5: Allow the script in `.claude/settings.json`**

In `permissions.allow`, after `"Bash(bash scripts/sync.sh *)",`, add:

```json
      "Bash(bash scripts/spending.sh *)",
```

Validate the JSON without running project code:

Run: `powershell -NoProfile -Command "Get-Content .claude/settings.json -Raw | ConvertFrom-Json | Out-Null; 'valid'"`
Expected: `valid`

- [ ] **Step 6: Commit**

Run: `bash scripts/sync.sh "spending: add spending rules, template, and categories list"`
Expected: `SYNC OK: pushed …`

---

### Task 5: Spending in the monthly summary

**Files:**
- Modify: `.claude/skills/summary/SKILL.md` (line 5 `allowed-tools`; section 3 Collect after the Inbox bullet, line 62; section 4 Weekly and monthly list, lines 102-111)

**Interfaces:**
- Consumes: `total FILE` and `delta CURRENT PREVIOUS` output formats from Tasks 1 and 2, and ledger paths from Task 4.
- Produces: the monthly summary `## Spending` section.

- [ ] **Step 1: Allow the script**

Line 5 becomes:

```yaml
allowed-tools: Read, Glob, Grep, Write, Edit, Bash(date *), Bash(bash scripts/sync.sh *), Bash(bash scripts/spending.sh *)
```

- [ ] **Step 2: Add the collect rule**

After the line ``- **Inbox**: list every note in `inbox/` except `.gitkeep`.``, add:

```markdown
- **Spending** (monthly only): if `spending/MONTH.md` exists for the month label, run `bash scripts/spending.sh total jarvis-vault/spending/MONTH.md`. Use only its output, never the ledger's stored Totals section. For the previous month, get the label with `date -d "START -1 month" +%Y-%m`. If that ledger exists, run `total` on it too, then `bash scripts/spending.sh delta CURRENT PREVIOUS` with the two TOTAL values. If `total` reports an error, write the error under `## Spending` instead of numbers.
```

- [ ] **Step 3: Add the section to the weekly and monthly list**

Replace items 7 to 9 of the **Weekly and monthly** list with:

```markdown
7. `## Spending` (monthly only, leave it out of weekly) — the format below
8. `## Next week` (weekly) or `## Next month` (monthly) — upcoming events, birthdays, and tasks due
9. `## Open tasks with no due date`
10. `## Inbox`

The Spending section, with every number copied from the script (add thousands separators for display only):

    - **Total: 1,284.35 CAD** (47 entries) · [[2026-10]]
    - Previous month: 1,102.80 CAD (+181.55)
    - By category:
      - groceries: 412.60 (32%)
    - Largest entries:
      - Saturday 2026-10-03: 61.70 shopping "headphones" (45.00 USD)

Leave out the Previous month line when there is no previous ledger. Show a converted entry's original amount and currency in brackets. With no ledger for the month, write `- None`.
```

- [ ] **Step 4: Commit**

Run: `bash scripts/sync.sh "summary: add spending section to monthly summary"`
Expected: `SYNC OK: pushed …`

---

### Task 6: README

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: the file names and commands from Tasks 1 to 5.
- Produces: user-facing setup and test docs.

- [ ] **Step 1: Install `jq`**

In Part 2 step 1, change `apt update && apt install -y git tmux curl ca-certificates openssh-client tzdata` to:

```bash
   apt update && apt install -y git tmux curl jq ca-certificates openssh-client tzdata
```

- [ ] **Step 2: Folder table**

After the `scripts/start-remote.sh` row, add:

```markdown
| `scripts/spending.sh` | Spending totals, currency conversion, and Bank of Canada rates. Reads and calculates only. |
| `scripts/test-spending.sh` | Offline tests for `spending.sh`. |
| `specs/` | Design specs and implementation plans. Excluded in Obsidian. |
```

After the `jarvis-vault/inbox/` row, add:

```markdown
| `jarvis-vault/spending/` | One spending ledger per month (CAD), and the list of categories. |
```

- [ ] **Step 3: Part 4 tests**

After test 6 (`/summary weekly`), add:

````markdown
Before the spending tests, run the script tests in the container (as the `vault` user):

```bash
cd ~/vault && bash scripts/test-spending.sh
```

Every line should say PASS, ending with `0 failed`. Then check one live rate: `bash scripts/spending.sh rate USD 2026-10-01` should print a rate and a date.

7. `Spent 14.50 on lunch, food.`
   Expected: Jarvis asks to confirm the new category "food". After your yes, `jarvis-vault/spending/` has the month's ledger with one row and Totals 14.50, plus `food` in `categories.md`.
8. `Spent 20 USD on a book, food.`
   Expected: the reply shows the Bank of Canada rate and the CAD amount, and the row's Original column shows `20.00 USD × …`.
9. `Delete the book.`
   Expected: Jarvis asks first, showing the entry's date with its weekday. After your yes, the row is gone and Totals is back to 14.50.
````

- [ ] **Step 4: Everyday phrases**

After the `/summary …` row, add:

```markdown
| "Spent 14.50 on lunch, food" | Adds a row to this month's ledger in `spending/`. Asks first for a new category. |
| "Spent 20 USD on …" | Converts to CAD with the Bank of Canada rate and shows the rate. |
| "Delete / change the … entry" | Asks for your yes, showing the date, then updates the ledger. |
| "How much have I spent this month?" | Answers from the ledger. Nothing is written. |
| "Recalculate my spending" | Rewrites the month's totals after you edit a ledger by hand. |
```

- [ ] **Step 5: What was tested**

After the `/summary` line in "What was tested", add:

```markdown
- Not tested: spending tracking. `scripts/spending.sh` and its tests were written without being run. Run `bash scripts/test-spending.sh` and tests 7 to 9 in Part 4 on the container before relying on it.
```

- [ ] **Step 6: Commit**

Run: `bash scripts/sync.sh "doc: document spending tracking in README"`
Expected: `SYNC OK: pushed …`

---

### Task 7: Homelab verification (the user runs this, after deploying)

This is the only task that runs anything. It happens on the homelab container, as the `vault` user, in `~/vault`.

- [ ] **Step 1: Get the latest code and install `jq`**

```bash
cd ~/vault && bash scripts/sync.sh --pull
sudo apt install -y jq    # or as root: apt install -y jq
```

- [ ] **Step 2: Run the offline tests**

Run: `bash scripts/test-spending.sh`
Expected: every line is `PASS`, ending with `N passed, 0 failed`, exit code 0. Any `FAIL` goes back to the authoring session with the printed expected and actual values.

- [ ] **Step 3: Live rate checks**

| Command | Expected |
|---|---|
| `bash scripts/spending.sh rate USD 2026-10-01` | A rate like `1.3xxx`, then `2026-10-01` |
| `bash scripts/spending.sh rate USD 2026-10-04` (a Sunday) | The rate dated Friday `2026-10-02` |
| `bash scripts/spending.sh rate XYZ 2026-10-01` | `SPENDING ERROR: the Bank of Canada publishes no rate for XYZ` |

If the unknown currency gives a different error, for example HTTP 400 instead of 404, note the actual response. Adjust `cmd_rate`'s status check in the authoring session.

- [ ] **Step 4: Phone tests**

Run Part 4 tests 7 to 9 from the Claude app. Then run `/summary monthly` and check that it has a `## Spending` section that matches the ledger.

- [ ] **Step 5: Mark as tested**

Once everything passes, ask Jarvis to update the README's "What was tested" line for spending tracking.
