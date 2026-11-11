---
name: claude-credito
description: Make a script, robot or scheduled job that calls `claude -p` use the plan's monthly API credit first, and the subscription when the API refuses, through the `claude-credito` command. Use when the user says "use my API credit for the robots", "run this script on the API credit", "claude-credito", "why did this job use my subscription?", "is the API credit being used?", "store my Console key", or when a `claude -p` job fails with "Credit balance is too low" or "Invalid API key".
---

# claude-credito

`claude-credito` takes the same arguments as `claude`. A call with `-p`/`--print` runs with the
user's Console API key (the plan's monthly API credit). If the API refuses (no credit left, bad key),
the same call runs again on the subscription and the API is paused for 6 hours. A call without `-p`
goes straight to `claude`: an interactive session is not covered by the credit.

## Find the command

```
command -v claude-credito || ls ~/.local/bin/claude-credito
```

Not there: it is installed by `install.sh` from the plugin's folder (`${CLAUDE_PLUGIN_ROOT}/install.sh`),
or from a clone of https://github.com/lucas-saldanha-werneck/api-credit. Show `./install.sh --dry-run`
first and ask before running it: it writes to `~/.local/bin`.

## Check the state first

```
claude-credito --credit-status
```

It prints whether a key is stored, whether the API is paused, which `claude` it runs, and the last
log lines. Each log line says where the call ran: `api rc=0`, `subscription (paused)`,
`subscription (no key stored ...)`, or `API REFUSED (...)` followed by `subscription rc=...`.

## Store the key

The key is a Console API key (Claude Console, API keys). Never ask the user to paste it in the
chat, and never put it on a command line. Tell the user to run this in their own terminal:

```
claude-credito --credit-store-key
```

It asks for the key with hidden input and stores it in the macOS Keychain (elsewhere, in
`~/.config/claude-credito/key`, mode 600). With a password manager, set `CLAUDE_CREDITO_KEY_COMMAND`
in `~/.config/claude-credito/config` to a command that prints the key; then `--credit-store-key`
needs no typing.

## Point a script at it

Read the script first and find how it calls claude. Then pick the smallest change:

1. The script has a setting or variable for the claude path: set it to `claude-credito` (full path
   for launchd or cron jobs, which have a short PATH).
2. The script calls a bare `claude` and you should not edit it: put the shim first on its PATH.
   `PATH="$HOME/.local/share/claude-credito/shim:$PATH" the-script`
3. Otherwise replace the path of `claude` in the call with the path of `claude-credito`.

For a tool that other people also use, detect it instead of requiring it: use `claude-credito` when
it exists, and `claude` when it does not.

Keep a backup of any file you change, and test with one real call. Then run
`claude-credito --credit-status` and show the user the new `api rc=0` line.

## Things to know

- Output is the same as claude's, but it arrives when the call ends: there is no streaming. Do not
  use it for a call whose output is read line by line while it runs (`--output-format stream-json`
  consumed live).
- A test of `claude -p` started from inside a Claude Code session inherits that session's
  environment and can give a false result. Test with a clean environment (`env -i HOME=... PATH=...`).
- With a key that the API rejects, `claude -p` in text mode can exit 0 and print the error as the
  answer. claude-credito reads the text, not the exit code.
- If the Console organization has paid credits or auto-reload on, the API does not refuse when the
  monthly credit ends: it uses the paid balance. Tell the user to check the Console billing page.
- `CLAUDE_CREDITO=off` in a job's environment sends that job to the subscription only.
- `claude-credito --credit-resume` ends the 6-hour pause (for example after the monthly credit renews).
