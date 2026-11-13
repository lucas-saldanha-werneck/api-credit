# Security Policy

## Reporting a vulnerability

Please report it privately: open the repository's **Security** tab and choose **Report a vulnerability**
(https://github.com/lucas-saldanha-werneck/api-credit/security/advisories/new). Please do not open a public issue for a
security problem.

## Supported versions

Only the latest release (0.1.8) is supported. Fixes go into a new release.

## What api-credit accesses

- Reads a Console API key from the macOS Keychain (item `claude-credito`) or from `~/.config/claude-credito/key`, and gives it to the `claude` it runs, only for `claude -p` calls and only in that process's environment.
- The key is never printed or logged. The log (`~/Library/Logs/claude-credito.log`) holds the time, route, exit code and folder; pause files are named after a short hash of the key.
- Runs your real `claude`; it makes no network requests of its own. `install.sh` copies files into `~/.local/bin`, `~/.local/share/claude-credito` and `~/.config/claude-credito`, and `--uninstall` removes the programs but keeps your key, config and log.
