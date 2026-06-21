# Contributing to Clinj

Thanks for helping build an honest Mac reclaimer. A few principles keep this safe and trustworthy:

## Non-negotiables
- **Never delete user data.** Every deletion must route through `assert_safe_path()` in
  `core/lib/safety.sh`. If you add a path, it must sit under an allowed prefix and outside every
  protected root. When in doubt, classify it `review` (quarantined, recoverable) — not `safe`.
- **Zero runtime dependencies.** Target **bash 3.2** (what ships on macOS). No `declare -A`,
  `mapfile`, or GNU-only flags. CI runs the macOS bash to enforce this.
- **Honest classification.** Each item declares what it is and *what regenerates it*. No vague
  "junk." If removing it costs the user a big re-download, mark it `aggressive`.

## Adding a cleaner
- Known, named tools → add a line to `core/lib/rules.sh` with full metadata.
- Whole categories of apps (e.g. a new Electron family) → prefer **structural detection** in
  `core/lib/discover.sh` so it works on machines we've never seen.

## Before opening a PR
```bash
shellcheck -S warning -e SC1090,SC1091 core/clinj.sh core/lib/*.sh bin/clinj
bash tests/test.sh
```

## Profiles
Profiles in `core/profiles/*.conf` only select categories + whether `aggressive` items are
included. They never widen safety.
