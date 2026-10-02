# Zohara Packages

Arch package repository for [Zohara OS](https://github.com/Zohaib8090/zohara).
This repo holds the database files that `pacman -Syu` reads to update
Zohara-specific packages on a running Zohara OS installation.

## How updates flow

```
   Source repo                This repo                       User's system
   ───────────                ─────────                       ─────────────
   zohara-settings  ──┐
   zohara-store      ──┤
   zohara-connect    ──┼──>  publish.yml  ──>  releases/latest/download/zohara.db
   ...               ──┘        │
                                 └──>  apps.json  (Store catalog)
                                 
                                                              [zohara-stable] in
                                                              /etc/pacman.conf
                                                                      │
                                                                      v
                                                                 pacman -Syu
                                                                 (auto)
```

## Release channels

Each channel is a separate GitHub release in this repo, with its own
`zohara.db`:

| Channel | Release tag    | pacman repo name | Notes |
|---------|----------------|------------------|-------|
| stable  | `stable`       | `[zohara-stable]` | Default. Auto-published on every push to `zohara-settings/main`. |
| beta    | `channel-beta` | `[zohara-beta]`   | Auto-published on every push to `zohara-settings/beta`. |
| alpha   | `channel-alpha`| `[zohara-alpha]`  | Manual publish only (Run workflow on this repo, or the admin site). |

pacman downloads `<repo name>.db`, so a system with `[zohara-stable]` in
`/etc/pacman.conf` fetches `zohara-stable.db`, not `zohara.db`. Every publish
therefore uploads the database under both names (`zohara.db` and
`zohara-<channel>.db`, plus the `.files` copies). If a channel's release only
has `zohara.db`, `pacman -Sy` fails with a 404 on every system using it and
no updates can be installed.

Users pick a channel once:
```bash
sudo zohara-channel set stable   # default
sudo zohara-channel set beta
sudo zohara-channel set alpha
```

The system writes the matching repo entry to `/etc/pacman.conf` and
refreshes the package database.

## Publishing a build by hand

Actions > "Publish Zohara Package" > Run workflow. Pick the source repository, paste the **run id** of a successful
build (the number in the run's URL), pick the channel (alpha is the default; use it to try things), and leave
the other two boxes empty to publish every package in the run's artifact. The admin site
(`zohara-updates-system`) starts the same workflow with the same inputs.

The workflow refuses anything it should not publish, before downloading a byte: a source repository that is not
on the allowed list (`scripts/validate-publish-inputs.sh`), a run that failed, was started by a pull request, or
is on the wrong branch for the channel (`scripts/verify-source-run.sh`). The package name and version come from the
package file itself (`scripts/read-pkginfo.sh`). `apps.json` (the Store catalog) is changed only by **stable**
publishes. Packages are not signed yet (`SigLevel = Optional TrustAll` on the installed systems): that is phase 5
of `zohara-updates-system/docs/PLAN.md`.

Several publishes can run at the same time. After uploading, the workflow re-reads the channel database and, if
another publish overwrote it, merges again.

Test the helper scripts offline: `bash scripts/test-publish-scripts.sh [some.pkg.tar.zst]`.

## Files in this repo

- `apps.json` — catalog consumed by the Zohara Software Store. Auto-patched
  on every **stable** publish.
- `scripts/` — the checks the publish workflow runs, and their tests.
- `.github/workflows/publish.yml` — receives a `repository_dispatch` event
  with the artifact URL, merges it into the channel's `zohara.db`, and
  uploads both back to the channel release.

## Adding a new package

1. Make the source repo emit a `repository_dispatch` event on release.
2. That's it. The `publish.yml` workflow handles everything else.
