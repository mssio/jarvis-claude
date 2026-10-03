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

1. Run `timedatectl show -p Timezone --value` to get the server's zone. If the command fails or prints nothing, the server zone is unknown.
2. Ask: `Which time zone should Jarvis use? The server is set to <zone>. Reply "yes" to use it, or give another, for example Europe/London.` If the server zone is unknown, ask instead: `Which time zone should Jarvis use? Give an Area/City name, for example America/Toronto.`
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

- **Clock:** if the chosen zone differs from the server's zone in step 3, or the server zone is unknown, include this line exactly, and say that dates and times are wrong until it is run:
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
