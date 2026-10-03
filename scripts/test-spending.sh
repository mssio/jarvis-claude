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

ledger "$tmp/nopipe.md" <<'EOF'
| 2026-10-02 | 14.50 | food | lunch | |
2026-10-06 | 1.00 | food | x |
EOF
expect_error "total: row without a leading pipe names its line" "line 15: not a table row" sp total "$tmp/nopipe.md"

printf '%s\n' '# Spending: October 2026' '' '## entries' '| 2026-10-02 | 14.50 | food | lunch | |' > "$tmp/noheading.md"
expect_error "total: missing Entries heading is an error, not 0.00" 'no "## Entries" table' sp total "$tmp/noheading.md"

expect_error "total: missing file" "no such file" sp total "$tmp/does-not-exist.md"
expect_error "total: no file given" "usage: total FILE" sp total

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

# --- rate (input checks only; they fail before any network call) ---

expect_error "rate: CAD is refused" "already in CAD" sp rate CAD 2026-10-01
expect_error "rate: lowercase cad is refused" "already in CAD" sp rate cad 2026-10-01
expect_error "rate: future date" "in the future" sp rate USD 2999-01-01
expect_error "rate: bad date" "not a date" sp rate USD 10/02/2026
expect_error "rate: bad currency code" "not a currency code" sp rate US 2026-10-01
expect_error "rate: missing date" "usage: rate CURRENCY DATE" sp rate USD

# --- results ---

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
