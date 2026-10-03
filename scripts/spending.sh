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
    /^## / { in_entries = ($0 ~ /^## Entries[ \t]*$/); if (in_entries) seen = 1; next }
    !in_entries { next }
    $0 ~ /^[ \t]*$/ { next }
    $0 !~ /^[ \t]*\|/ { fail("line " NR ": not a table row (every row starts with |)") }
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
      if (!seen) { print "ERR\tno \"## Entries\" table found"; exit 3 }
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
  # An unknown series comes back as 404 (or 400 on some API versions).
  case "$code" in
    400|404) die "the Bank of Canada publishes no rate for $cur" ;;
  esac
  [ "$code" = "200" ] || die "the Bank of Canada returned HTTP $code"

  result="$(printf '%s' "$body" | jq -r --arg s "FX${cur}CAD" '
    [.observations[]? | select(.[$s].v != null) | {d, v: .[$s].v}]
    | sort_by(.d) | last
    | if . == null then empty else "\(.v)\t\(.d)" end
  ' 2>/dev/null)" || die "could not read the Bank of Canada response"
  [ -n "$result" ] || die "no $cur rate published from $start to $day"
  printf '%s\n' "$result"
}

case "${1:-}" in
  total)   shift; cmd_total "$@" ;;
  convert) shift; cmd_convert "$@" ;;
  delta)   shift; cmd_delta "$@" ;;
  rate)    shift; cmd_rate "$@" ;;
  *) die "usage: spending.sh total FILE | convert AMOUNT RATE | delta CURRENT PREVIOUS | rate CURRENCY DATE" ;;
esac
