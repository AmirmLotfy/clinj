<div align="center">

<img src="docs/icon.png" width="128" alt="Clinj icon">

# Clinj

**An honest, open-source disk reclaimer for macOS.**

Finds what's actually safe to delete on *your* Mac — not a hardcoded list — tells you exactly
what each thing is and what regenerates it, and keeps anything uncertain **recoverable**.

No telemetry. No subscription. ~600 lines of auditable shell. Zero runtime dependencies.

</div>

---

## Why another cleaner?

Most Mac "cleaners" are opaque, paid, and ship a fixed list of paths. Clinj is the opposite:

- **Adapts to your machine.** It *discovers* cleanable data structurally — auto-detecting every
  Electron app (Cursor, Claude, Slack, Postman, Canva, whatever you have) and every Chromium
  browser profile by their on-disk shape, not by a name we guessed.
- **Tells the truth.** Every item is classified `safe` / `aggressive` / `review` and labeled with
  *what regenerates it*. You always know the cost of deleting.
- **Recoverable by default for anything uncertain.** Unknown caches are moved to a **quarantine**
  you can `restore` from — not `rm -rf`'d. Known-regenerable caches are deleted directly so you
  actually get the space back.
- **Refuses to touch your stuff.** A single `assert_safe_path()` guard hard-blocks Documents,
  Desktop, Downloads, Pictures, iCloud Drive, Keychains, Mail, SSH/GPG keys — fail-closed.

> **On "RAM boosting":** macOS manages memory well. Clinj offers a `ram` command that runs
> `purge` (frees inactive memory) and is honest that gains are usually modest. It never kills
> or disturbs running apps. This is a footnote, not a headline.

## Install

**CLI (zero dependencies, works today):**

```bash
# Homebrew
brew install --HEAD AmirmLotfy/clinj/clinj

# or one-line installer
curl -fsSL https://raw.githubusercontent.com/AmirmLotfy/clinj/main/install.sh | bash

# or from source, no build step
git clone https://github.com/AmirmLotfy/clinj && cd clinj && ./bin/clinj scan
```

**App (window + menu-bar):** build it from source —

```bash
git clone https://github.com/AmirmLotfy/clinj && cd clinj
bash app/build-app.sh --install        # → /Applications/Clinj.app
```

> The prebuilt `.app` isn't notarized yet, so a downloaded build needs a one-time
> **right-click → Open** (or System Settings → Privacy & Security → *Open Anyway*).
> Building from source as above avoids that.

## Usage

```bash
clinj scan                          # what's reclaimable, grouped, with sizes
clinj scan --profile developer      # tailored to a developer machine
clinj scan --all --json             # full machine-readable catalog (for tooling/UI)

clinj clean --profile developer --dry-run     # preview — deletes nothing
clinj clean --profile developer                # do it (regenerable caches freed now)
clinj clean --include-review                    # also sweep unknown caches → quarantine

clinj restore                       # undo the last quarantined clean
clinj sweep --older-than 7          # permanently empty quarantine older than N days
clinj profiles                      # list profiles
```

### Profiles

| Profile | For | Includes |
|---------|-----|----------|
| `minimal`   | anyone, safest | Trash, system caches |
| `general`   | everyday Mac | browser + app caches, system, Trash |
| `designer`  | creative work | general + iOS/sim caches |
| `developer` | full toolchain | npm/pnpm/yarn/pip/uv/go/cargo/gradle/cocoapods/Xcode/Docker + apps + browsers, incl. aggressive items |

## Safety model

| Class | Meaning | What Clinj does |
|-------|---------|-----------------|
| `safe` | regenerable cache | deletes directly (space freed now) |
| `aggressive` | regenerable but heavy to refetch | only with `--aggressive` / developer profile |
| `review` | unrecognized / uncertain | **moved to quarantine, restorable** |

Everything passes `assert_safe_path()`. Protected roots are never touched even if a rule names them.

## Architecture

```
core/
  clinj.sh            CLI: scan / clean / restore / sweep / profiles / ram
  lib/
    discover.sh       dynamic detection (Electron, browsers, unknown caches) + known rules
    rules.sh          declarative catalog of named tools, with metadata
    safety.sh         assert_safe_path() — the fail-closed guardrail
    quarantine.sh     dispose() vs quarantine_move()/restore/sweep
    util.sh           sizing, formatting, JSON, logging
  profiles/           minimal · general · designer · developer
```

A native **SwiftUI app** (menu-bar + window) sits on top of this engine — see the roadmap.

## Roadmap

- [x] Dynamic discovery + classification engine (this repo)
- [x] Quarantine/restore safety model + profiles
- [ ] SwiftUI app (categorized list, sizes, scheduling) over the JSON catalog
- [ ] Code signing + notarization; distribute via GitHub Releases + Homebrew cask
- [ ] Scheduled background reclaim (launchd) with a friendly config UI

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The bar: never touch user data, stay bash-3.2 clean,
classify honestly. Run `bash tests/test.sh` and `shellcheck` before a PR.

## License

[MIT](LICENSE).
