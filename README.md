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

## OCI Object Storage (main store) and the ISO

Since phase 3 of `zohara-updates-system/docs/PLAN.md` (written 2026-10-04) every publish also copies the channel's
files to OCI Object Storage (`scripts/oci-upload.sh`: packages first, database files last, public copy compared
byte for byte). GitHub Releases is still the address installed systems use, so a failure of the OCI copy is only a
warning. The step is skipped while the secret below does not exist.

| Secret (repo Settings > Secrets > Actions) | What it is |
|---|---|
| `OCI_PACKAGES_PAR` | OCI pre-authenticated request URL that allows object **writes** to the public bucket `zohara-packages` (ends in `/o/`). Expires; renew it. |
| `OCI_ISO_PAR` | the same kind of URL for the public bucket `zohara-os` (the ISO) |

Public bucket addresses (region `ap-mumbai-1`, namespace `bm27e3oxmp04`):
`https://objectstorage.ap-mumbai-1.oraclecloud.com/n/bm27e3oxmp04/b/zohara-packages/o/<tag>/<file>` for packages and
`.../b/zohara-os/o/<file>` for the ISO. A write URL cannot delete: remove old files in the OCI console (the free tier
holds 20 GB in total).

**Promote ISO** (`.github/workflows/promote-iso.yml`): Actions > Promote ISO > Run workflow, with the run id of a
successful "Build Zohara OS ISO" run in `Zohaib8090/zohara` (CI keeps that artifact only 30 days). It uploads the
image, a `.sha256` file and `latest.json` to `zohara-os`, then downloads the public copy and compares the hash.
SourceForge stays a manual mirror (`zohara/scripts/upload-iso.sh`).

Offline tests: `bash scripts/test-oci-upload.sh` (a local fake bucket, `scripts/fake-oci-server.py`).

## Package signing

Packages and the database can be signed with Zohara's key, and machines made to refuse anything else. The key, the
rollout order (the key must reach machines **before** signing is switched on) and the tests are in
[docs/SIGNING.md](docs/SIGNING.md). Status: key made, keyring package published, signing off, machines still accept
unsigned packages.

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
