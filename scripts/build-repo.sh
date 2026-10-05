#!/usr/bin/env bash
# build-repo.sh DIR CHANNEL
# (Re)builds the channel's pacman database from every package in DIR, and signs the packages and the database when
# the signing key secret is present (see sign-lib.sh). Leaves, next to the packages:
#   zohara.db  zohara.files           what a bare repository named "zohara" would fetch
#   zohara-CHANNEL.db / .files        what [zohara-CHANNEL] in pacman.conf fetches ("<section>.db")
#   each of those plus *.tar.gz, and a .sig for each when signing
# pacman fetches "<section name>.db": [zohara-stable] asks for zohara-stable.db. A release with only zohara.db made
# `pacman -Sy` fail with a 404 on every installed system (found 2026-09-30), hence all the copies. Real files, not
# symlinks, because a release asset cannot be a link.
set -euo pipefail
dir="${1:?usage: build-repo.sh DIR CHANNEL}"; channel="${2:?usage: build-repo.sh DIR CHANNEL}"
[[ "$channel" =~ ^(stable|beta|alpha)$ ]] || { echo "::error::bad channel '$channel'"; exit 1; }
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sign-lib.sh
source "$here/sign-lib.sh"
signing_setup

cd "$dir"; shopt -s nullglob
# Stale database copies (and their signatures) go first; package signatures stay.
rm -f zohara.db* zohara.files* "zohara-$channel.db"* "zohara-$channel.files"*

sign_args=()
if [ "$SIGNING" = 1 ]; then
  sign_missing_packages .
  sign_args=(--sign --key "$GPGKEY")
fi
# -n: when two versions of one package are present, keep the newer one
repo-add -n "${sign_args[@]}" zohara.db.tar.gz ./*.pkg.tar.zst
rm -f zohara.db zohara.files zohara.db.sig zohara.files.sig
cp zohara.db.tar.gz zohara.db
[ -e zohara.db.tar.gz.sig ] && cp zohara.db.tar.gz.sig zohara.db.sig
for ext in db files; do
  [ -e "zohara.$ext.tar.gz" ] || continue
  cp -L "zohara.$ext.tar.gz" "zohara-$channel.$ext.tar.gz"
  cp -L "zohara.$ext.tar.gz" "zohara-$channel.$ext"
  if [ -e "zohara.$ext.tar.gz.sig" ]; then
    cp -L "zohara.$ext.tar.gz.sig" "zohara-$channel.$ext.tar.gz.sig"
    cp -L "zohara.$ext.tar.gz.sig" "zohara-$channel.$ext.sig"
    [ "$ext" = files ] && cp -L "zohara.$ext.tar.gz.sig" "zohara.$ext.sig"
  fi
done
echo "repository built in $dir for $channel (signed: $SIGNING)"
