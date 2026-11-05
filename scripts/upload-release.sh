#!/usr/bin/env bash
# Uploads a built channel repository to its GitHub release in the order that can never leave the channel broken:
#   1. the packages this run publishes (and their signatures),
#   2. a check that GitHub now really lists them,
#   3. every other package / signature,
#   4. the database files, the one pacman reads (zohara-CHANNEL.db) last.
# A database that names a package file that is not in the release makes every machine on the channel fail with a 404, which
# is what a GitHub 500 in the middle of the old single upload did on 2026-11-03. Now a failure before step 4 leaves the old,
# consistent database in place and only adds files nobody references yet.
#
#   scripts/upload-release.sh TAG REPO CHANNEL REPO_DIR INCOMING_DIR
# GH overrides the gh command (tests).
set -euo pipefail
tag="${1:?usage: upload-release.sh TAG REPO CHANNEL REPO_DIR INCOMING_DIR}"; repo="${2:?}"; channel="${3:?}"
dir="${4:?}"; incoming="${5:?}"
GH="${GH:-gh}"

upload() { # upload FILE... (relative to $dir); one retry, like before
  [ "$#" -gt 0 ] || return 0
  ( cd "$dir"
    "$GH" release upload "$tag" "$@" --repo "$repo" --clobber \
      || { echo "::warning::upload failed, retrying once"; sleep "${UPLOAD_RETRY_SLEEP:-5}"; "$GH" release upload "$tag" "$@" --repo "$repo" --clobber; } )
}

shopt -s nullglob
new=()
for p in "$incoming"/*.pkg.tar.zst; do
  b="$(basename "$p")"; new+=("$b"); [ -f "$dir/$b.sig" ] && new+=("$b.sig")
done
[ "${#new[@]}" -gt 0 ] || { echo "::error::no package to publish in $incoming"; exit 1; }

echo "1/3 packages of this publish: ${new[*]}"
upload "${new[@]}"

# 2. they must be there before anything points at them
listed="$("$GH" release view "$tag" --repo "$repo" --json assets --jq '.assets[].name')"
for f in "${new[@]}"; do
  grep -qxF "$f" <<<"$listed" || { echo "::error::$f is not in release $tag after the upload; the database was NOT touched"; exit 1; }
done

# 3. everything else that is not a database file (older packages, signatures)
rest=(); dbs=(); last=()
for f in "$dir"/*; do
  b="$(basename "$f")"
  case " ${new[*]} " in *" $b "*) continue;; esac
  case "$b" in
    "zohara-$channel.db"|"zohara-$channel.db.tar.gz"|"zohara-$channel.db.sig"|"zohara-$channel.db.tar.gz.sig") last+=("$b");;
    *.db|*.db.*|*.files|*.files.*) dbs+=("$b");;
    *) rest+=("$b");;
  esac
done
echo "2/3 other packages and signatures: ${#rest[@]} file(s)"
upload "${rest[@]}"
# 4. the databases: the copies pacman does not read first, the channel's own database last
echo "3/3 databases"
upload "${dbs[@]}"
tail_files=()
for want in "zohara-$channel.db.tar.gz" "zohara-$channel.db.tar.gz.sig" "zohara-$channel.db.sig" "zohara-$channel.db"; do
  for f in "${last[@]}"; do [ "$f" = "$want" ] && tail_files+=("$f"); done
done
for f in "${tail_files[@]}"; do upload "$f"; done
echo "upload done"
