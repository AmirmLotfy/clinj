# Launch posts

Honest, low-hype copy. The dev/Show-HN crowd punishes marketing speak — lead with *what it is*
and *what's different*, admit the limits (RAM, notarization), and link the source.

---

## Show HN

**Title** (the post links to the repo URL — keep it factual, ≤ 80 chars):

> Show HN: Clinj – an open-source macOS disk reclaimer that shows what it deletes

**URL:** https://github.com/AmirmLotfy/clinj

**First comment (post immediately after submitting):**

> I kept running low on disk on a 256GB MacBook and didn't trust the usual "cleaner" apps —
> they're opaque, paid, and the "RAM booster" stuff is mostly snake oil. So I built Clinj.
>
> What's different:
> - **It discovers, it doesn't hardcode.** Instead of a fixed path list, it detects Electron
>   apps and Chromium browsers *structurally*, so it finds caches for apps I've never heard of.
> - **Every item is classified** `safe` / `aggressive` / `review` and labeled with *what
>   regenerates it*, so you know the cost before deleting.
> - **Uncertain stuff is recoverable.** Unknown caches go to a quarantine you can `restore`
>   from; only known-regenerable caches are deleted outright.
> - **Zero dependencies, auditable.** ~600 lines of bash (3.2-compatible) behind a fail-closed
>   `assert_safe_path()` that hard-blocks Documents/Desktop/Downloads/Keychains/etc. There's a
>   small SwiftUI app on top, but the engine is just shell and emits a JSON catalog.
>
> Honest limits: it's not a "RAM booster" — there's a `purge` command but I'm upfront that
> gains are modest. The GUI app isn't notarized yet, so for now you build it from source; the
> CLI installs via Homebrew.
>
>     brew install AmirmLotfy/clinj/clinj
>     clinj scan
>
> MIT licensed. Would love feedback on the safety model and on caches I'm misclassifying.

---

## r/macapps

**Title:**

> [Free / Open-source] Clinj – a Mac disk cleaner that shows you exactly what it deletes (and lets you undo)

**Body:**

> I made a free, open-source disk reclaimer for macOS because I wanted something *transparent* —
> no subscription, no telemetry, and no vague "junk" buckets.
>
> Clinj scans your Mac, **auto-detecting** app and browser caches (it finds apps by how they
> store data, so it works even for apps it's never seen), and shows everything grouped with
> sizes and a plain-English note on **what regenerates each item**. You pick a profile
> (General / Designer / Developer), review, and clean. Anything it isn't sure about is moved to
> a **recoverable quarantine** instead of deleted, so you can undo.
>
> It never touches your Documents, Desktop, Downloads, Photos, or app settings — that's enforced
> in code, not just promised.
>
> [demo gif] [screenshots]
>
> CLI: `brew install AmirmLotfy/clinj/clinj`. GUI app builds from source (not notarized yet).
> Source + details: https://github.com/AmirmLotfy/clinj — feedback very welcome.

---

## r/commandline (CLI angle)

**Title:**

> Clinj: a zero-dependency macOS disk-reclaimer CLI that classifies caches and quarantines the unknowns

**Body:**

> `clinj scan` discovers reclaimable caches (dev toolchains, Electron apps, browsers) by probing
> the filesystem structurally rather than from a hardcoded list, classifies each as
> safe/aggressive/review, and prints them grouped with sizes. `clinj clean --profile developer`
> frees the safe ones and moves anything uncertain to a restorable quarantine. Pure bash
> (3.2-compatible), one fail-closed safety guard, emits a JSON catalog. MIT.
>
>     brew install AmirmLotfy/clinj/clinj && clinj scan

---

## Posting tips
- **Show HN:** post Tue–Thu ~8–10am ET. Submit the repo URL, then immediately add the first
  comment above. Reply to every comment for the first few hours.
- **r/macapps:** flair as "Free" / open-source. Lead with the GIF. Mods like transparency about
  it being your own project — say so.
- **Also worth:** open a PR adding Clinj to `awesome-mac` and `awesome-macos-command-line`.
  Post to r/macOS, r/swift (the SwiftUI-over-shell architecture), and Lobsters (`show` tag).
- **Product Hunt** once the app is notarized (a smooth download matters there).
