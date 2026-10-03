#!/usr/bin/env bash
# Spending arithmetic for the Jarvis vault. It only reads and calculates; it never writes notes.
#
#   bash scripts/spending.sh total FILE            totals for one month's ledger
#   bash scripts/spending.sh convert AMOUNT RATE   AMOUNT x RATE, rounded to cents (half up)
#   bash scripts/spending.sh delta CURRENT PREV    signed difference, for example +181.55
#   bash scripts/spending.sh rate CUR DATE         rate from CUR to the home currency for DATE,
#                                                  or the last one published before it
#   bash scripts/spending.sh check-currency CUR    ok if the Bank of Canada publishes CUR
#
# The home currency is "currency" in the vault's settings.md (written by /setup).
# JARVIS_SETTINGS can point to another settings file (the tests use this).
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

case "${1:-}" in
  total)          shift; cmd_total "$@" ;;
  convert)        shift; cmd_convert "$@" ;;
  delta)          shift; cmd_delta "$@" ;;
  rate)           shift; cmd_rate "$@" ;;
  check-currency) shift; cmd_check_currency "$@" ;;
  *) die "usage: spending.sh total FILE | convert AMOUNT RATE | delta CURRENT PREVIOUS | rate CURRENCY DATE | check-currency CURRENCY" ;;
esac
