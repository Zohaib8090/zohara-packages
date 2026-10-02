#!/usr/bin/env bash
# Prints "<pkgname> <pkgver>" for a .pkg.tar.zst, read from the package's own .PKGINFO. The name and version that
# end up in the database and apps.json come from here, not from whatever the dispatch claimed.
set -euo pipefail
f="${1:?usage: read-pkginfo.sh FILE.pkg.tar.zst}"
info="$(tar --zstd -xOf "$f" .PKGINFO 2>/dev/null)" || { echo "not a readable package: $f" >&2; exit 1; }
name="$(sed -n 's/^pkgname = //p' <<<"$info" | head -1)"
ver="$(sed -n 's/^pkgver = //p' <<<"$info" | head -1)"
[ -n "$name" ] && [ -n "$ver" ] || { echo "no pkgname/pkgver in $f" >&2; exit 1; }
echo "$name $ver"
