# Changelog

All notable changes to this project are documented here. Versions follow [Semantic Versioning](https://semver.org/).

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
