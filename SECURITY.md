# Security Policy

## Reporting a vulnerability

Please report it privately: open the repository's **Security** tab and choose **Report a vulnerability**
(https://github.com/lucas-saldanha-werneck/api-credit/security/advisories/new). Please do not open a public issue for a
security problem.

## Supported versions

Only the latest release is supported. Fixes go into a new release.

## What api-credit accesses

- Reads a Console API key from `CLAUDE_CREDITO_KEY`, the macOS Keychain (item `claude-credito`) or `~/.config/claude-credito/key` (mode 600). It passes the key as `ANTHROPIC_API_KEY`, only to the `claude -p` calls it runs, so every tool that call runs inherits it too. `--credit-store-key` hands the key to `security` through stdin. If you set `CLAUDE_CREDITO_KEY_COMMAND`, it runs that command to get the key.
- The full key is never printed or logged; `--credit-status` shows only its last 4 characters. The log (`~/Library/Logs/claude-credito.log`) holds the time, route, exit code, refusal reason and folder. Pause files in `~/.local/state/claude-credito/` are named after a short hash of the key.
- During each `claude -p` call it keeps copies of stdin, stdout and stderr in a temporary folder under `$TMPDIR`, deleted when the call ends. In text mode it reads that call's transcript in `~/.claude/projects/` to see whether the model answered. When the API refuses the key and no turn ran, it runs the same call again on your subscription.
- Runs your real `claude`; it makes no network requests of its own. `install.sh` copies files into `~/.local/bin`, `~/.local/share/claude-credito` and `~/.config/claude-credito`, and `--uninstall` removes the programs but keeps your key, config and log. The shim in `~/.local/share/claude-credito/shim` sends any bare `claude` call to `claude-credito` for a script whose PATH puts that folder first.
