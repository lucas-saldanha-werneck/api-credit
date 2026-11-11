# api-credit

Run your `claude -p` scripts on your plan's monthly API credit first, and on your subscription when
the API refuses. One command, `claude-credito`, that you call instead of `claude`.

Some Claude plans come with a monthly API credit. It pays for `claude -p` and the Agent SDK only when
they run with a Console API key. Scripts and scheduled jobs that call a plain `claude -p` use the
subscription instead, and the credit expires unused. `claude-credito` adds the key for those calls,
and falls back to the subscription when the credit runs out, so a job never stops for lack of credit.

## Example

```
$ echo "Summarize this log" | claude-credito -p --model sonnet
The log shows three failed logins and one restart.

$ claude-credito --credit-status
key: stored (ends in …x9Qw)
pause: off
claude: /Users/you/.local/bin/claude
log: /Users/you/Library/Logs/claude-credito.log
2026-11-11T06:20:53-0300 api rc=0 (~/work/reports)
```

When the API refuses:

```
2026-11-12T09:00:01-0300 API REFUSED (Credit balance is too low, rc=1); the same call goes to the subscription; API paused 21600s (~/work/reports)
2026-11-12T09:00:04-0300 subscription rc=0 (~/work/reports)
2026-11-12T09:30:00-0300 subscription (paused) (~/work/reports)
```

## How it decides

| The call | Where it runs |
|---|---|
| No `-p` / `--print` (an interactive session) | plain `claude`, no key |
| `CLAUDE_CREDITO=off`, or the caller already set `ANTHROPIC_API_KEY` | plain `claude`, untouched |
| The API refused less than 6 hours ago | subscription |
| No key stored | subscription |
| Anything else | API, with your key. A short reply with "Credit balance is too low", "Invalid API key" or another billing or key error starts the 6-hour pause, and the same call (same arguments, same stdin) runs again on the subscription |

The output, the error output and the exit code are the ones `claude` gave. One notice that Claude
Code prints when a key is set ("claude.ai connectors are disabled because ANTHROPIC_API_KEY...") is
removed, because it is not part of the answer.

## Install

```
git clone https://github.com/lucas-saldanha-werneck/api-credit
cd api-credit
./install.sh --dry-run    # shows what it would do
./install.sh              # copies claude-credito to ~/.local/bin and the PATH shim to ~/.local/share/claude-credito/shim
claude-credito --credit-store-key   # asks for your Console API key, hidden
claude-credito --credit-status
```

The key goes to the macOS Keychain; on other systems, to `~/.config/claude-credito/key` (mode 600).
It is never written to the log.

The plugin adds a skill, so you can ask Claude to point a script at the credit or to check where a
job ran:

```
/plugin marketplace add lucas-saldanha-werneck/claude-plugins
/plugin install api-credit@lucas-plugins
```

The plugin is called `api-credit` because Claude Code reserves plugin names that start with
`claude-`. The skill uses the `claude-credito` installed by `install.sh`, so run that too.

Requires `bash` and Claude Code (`claude`).

## Use it in a script

- The script has a setting for the claude path: set it to `claude-credito`. In a launchd or cron job
  use the full path (`~/.local/bin/claude-credito`), because those have a short PATH.
- The script calls a bare `claude` and you do not want to edit it: put the shim first on its PATH.

  ```
  PATH="$HOME/.local/share/claude-credito/shim:$PATH" ./nightly-report.sh
  ```

- In a tool that other people use, detect it: `claude-credito` when it is installed, `claude` when
  it is not.

## Settings

Environment variables, or `KEY=VALUE` lines in `~/.config/claude-credito/config` (the environment
wins). `install.sh` writes a starter file with every line commented out, and never changes a file
that is already there.

| Variable | Default | Meaning |
|---|---|---|
| `CLAUDE_CREDITO` | on | `off`: never use the API |
| `CLAUDE_CREDITO_REAL` | the first `claude` on PATH that is not this tool | The `claude` to run |
| `CLAUDE_CREDITO_KEY` | the stored key | The key itself, for one call |
| `CLAUDE_CREDITO_KEY_COMMAND` | empty | A command that prints the key (your password manager). `--credit-store-key` runs it instead of asking |
| `CLAUDE_CREDITO_KEYCHAIN` | on | `off`: keep the key in the key file, not in the macOS Keychain |
| `CLAUDE_CREDITO_PAUSE_S` | `21600` | Seconds on the subscription after a refusal |
| `CLAUDE_CREDITO_LOG` | `~/Library/Logs/claude-credito.log` on macOS, `~/.local/state/claude-credito/claude-credito.log` elsewhere | Log file: one line per call, no prompt, no answer, no key |
| `CLAUDE_CREDITO_STATE` | `~/.local/state/claude-credito` | Folder of the pause file |
| `CLAUDE_CREDITO_CONFIG` | `~/.config/claude-credito/config` | The config file |

Commands: `--credit-status`, `--credit-store-key`, `--credit-resume` (ends the pause now),
`--credit-help`, `--credit-version`.

## Limits

- **No streaming.** The output arrives when the call ends, because the tool must read the reply
  before it decides to repeat the call. Do not use it where the output is read while it runs.
- **Paid credits.** If your Console organization has paid credits or auto-reload on, the API does not
  refuse when the monthly credit ends: it spends the paid balance. Turn auto-reload off if you want
  the fallback to the subscription.
- **What the credit covers** is Anthropic's rule and can change. Check your plan's help page.
- A refusal costs the time of one failed call (about 2 seconds with a small prompt), once per pause.
- A reply shorter than 6000 bytes that contains one of the refusal texts is treated as a refusal.

## Tests

```
bash tests/run.sh
```

40 checks with a fake `claude`, a fake HOME and no Keychain. They run on macOS and Linux in CI.

## Uninstall

```
./install.sh --uninstall
```

Removes `claude-credito` and the shim. Your config, stored key and log stay. Scripts that call
`claude-credito` must be pointed back at `claude`.

## License

MIT
