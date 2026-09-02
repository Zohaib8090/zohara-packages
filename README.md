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
| alpha   | `channel-alpha`| `[zohara-alpha]`  | Manual publish only (`workflow_dispatch` on this repo). |

Users pick a channel once:
```bash
sudo zohara-channel set stable   # default
sudo zohara-channel set beta
sudo zohara-channel set alpha
```

The system writes the matching repo entry to `/etc/pacman.conf` and
refreshes the package database.

## Files in this repo

- `apps.json` — catalog consumed by the Zohara Software Store. Auto-patched
  on every publish.
- `.github/workflows/publish.yml` — receives a `repository_dispatch` event
  with the artifact URL, merges it into the channel's `zohara.db`, and
  uploads both back to the channel release.

## Adding a new package

1. Make the source repo emit a `repository_dispatch` event on release.
2. That's it. The `publish.yml` workflow handles everything else.
