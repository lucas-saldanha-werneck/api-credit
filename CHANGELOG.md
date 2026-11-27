# Changelog

All notable changes to this project are documented here. Versions follow [Semantic Versioning](https://semver.org/).

## [0.4.0] - 2026-11-27
- Long-lived subscription token: `claude-credito --credit-store-oauth` copies a token made by `claude setup-token` (printed by `CLAUDE_CREDITO_OAUTH_COMMAND`) to the macOS Keychain. Every `-p` call that goes to the subscription (no key, API paused, API refused, `CLAUDE_CREDITO=off`) then runs with `CLAUDE_CODE_OAUTH_TOKEN`, so scripts do not depend on the interactive login expiring. A token the caller already set is kept. `CLAUDE_CREDITO_OAUTH=off` turns it off.
- That token has no claude.ai connectors and no Remote Control, and `claude --bare` ignores it. Calls without `-p` never get it.
- `--credit-status` shows whether the token is stored (never the token). The log marks those calls with `[1y token]`.

## [0.3.0] - 2026-11-21
- Preflight: before a real call, a 1-token request (`claude-haiku-5-5`) checks the key. A credit/key refusal there sends the call straight to the subscription, with no error for the caller and nothing to repeat (works with tools, `--no-session-persistence`, any output format). An OK is cached `CLAUDE_CREDITO_PREFLIGHT_S` seconds (default 600). Network errors, 429 and 5xx do not count as a refusal. `CLAUDE_CREDITO_PREFLIGHT=off` disables it.
- Default pause is now 24 h (`CLAUDE_CREDITO_PAUSE_S=86400`): the API is checked once a day, and used again by itself when the credit is back.
- A call that already ran a tool when the credit ended is still not repeated (documented).

## [Unreleased]
- A refused call with `--tools ""` + `--strict-mcp-config` (no tool can run) is repeated on the subscription even with `--no-session-persistence`, where there is no transcript to prove it.

## [0.2.0] - 2026-11-13
- Renamed the skill to `api-credit` (the old name broke the skill schema). The `claude-credito` command keeps its name.
- Skill frontmatter has `version` and `tags`; the skill has Purpose, Prerequisites, Limitations and Troubleshooting sections; the description is in the third person.
- README: demo video and badges; adds SECURITY.md.

## [0.1.8] - 2026-11-13
- Skill author, Instructions and Examples sections.

## [0.1.7] - 2026-11-12
- Feeds `claude` stdin through an anonymous pipe instead of a named FIFO.

## [0.1.6] - 2026-11-12
- Signals to the wrapper reach `claude`; stdin goes through `tee`, so a silent open stdin no longer hangs.
- Output is printed byte for byte; one pause file per key; the key file is written safely (600, renamed over).

## [0.1.5] - 2026-11-11
- A refused call is repeated on the subscription only when it is proven that no turn ran.

## [0.1.4] - 2026-11-11
- Points to the catalog repo's new name, `lucas-tools`.

## [0.1.3] - 2026-11-11
- Catalog renamed to `lucas-tools`.

## [0.1.2] - 2026-11-11
- `install.sh --dry-run` no longer prints "installed".

## [0.1.1] - 2026-11-11
- `install.sh` replaces files by rename, so a running job keeps the old one.
- Reads the pause file's time with GNU `stat` first (Linux).

## [0.1.0] - 2026-11-11
- First release: `claude -p` on the monthly API credit first, on the subscription when the API refuses.
