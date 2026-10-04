#!/usr/bin/env bash
# Copies a channel's files to OCI Object Storage (the main download location; GitHub Releases is the mirror).
#
#   scripts/oci-upload.sh PREFIX DIR
#
#   PREFIX  the folder in the bucket, e.g. "stable" or "channel-beta" (the release tag)
#   DIR     a directory with the .pkg.tar.zst files and the database files (zohara*.db, zohara*.files, ...)
#
# Environment:
#   OCI_PACKAGES_PAR   pre-authenticated request URL that allows object WRITES to the packages bucket, ending in
#                      "/o/" (a secret; it is the only credential this script needs, there is no OCI login)
#   OCI_PUBLIC_BASE    public read address of the same bucket, ending in "/o/"
#   CHANNEL            stable | beta | alpha (names the database files that get checked)
#
# Order matters: packages first, database files last, so a client never reads a database that lists a package
# which is not there yet. A package already in the bucket with the same size is not uploaded again. At the end the
# public copy of the database is downloaded and compared with the local one.
set -euo pipefail

prefix="${1:?usage: oci-upload.sh PREFIX DIR}"; dir="${2:?usage: oci-upload.sh PREFIX DIR}"
: "${OCI_PACKAGES_PAR:?OCI_PACKAGES_PAR is not set}"; : "${OCI_PUBLIC_BASE:?OCI_PUBLIC_BASE is not set}"
OCI_PACKAGES_PAR="$(printf %s "$OCI_PACKAGES_PAR" | tr -d "[:space:]")"; OCI_PUBLIC_BASE="$(printf %s "$OCI_PUBLIC_BASE" | tr -d "[:space:]")"  # a pasted secret may end in a newline
: "${CHANNEL:?CHANNEL is not set}"
[[ "$OCI_PACKAGES_PAR" == */o/ && "$OCI_PUBLIC_BASE" == */o/ ]] || { echo "::error::both addresses must end in /o/"; exit 1; }
[[ "$prefix" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "::error::bad prefix '$prefix'"; exit 1; }

enc() { jq -rn --arg s "$1" '$s|@uri'; }
put() { # put FILE NAME
  curl -fsS --retry 4 --retry-delay 3 --retry-all-errors -X PUT --upload-file "$1" -H 'Content-Type: application/octet-stream' \
    "$OCI_PACKAGES_PAR$prefix/$(enc "$2")" -o /dev/null
}
remote_size() { curl -sI --retry 2 "$OCI_PUBLIC_BASE$prefix/$(enc "$1")" | awk 'tolower($1)=="content-length:"{gsub("\r","",$2); print $2+0}'; }

up=0; skipped=0
shopt -s nullglob
for f in "$dir"/*.pkg.tar.zst; do
  name="$(basename "$f")"; size="$(stat -c%s "$f")"
  if [ "$(remote_size "$name")" = "$size" ]; then skipped=$((skipped+1)); continue; fi
  echo "uploading $name ($size bytes)"; put "$f" "$name"; up=$((up+1))
done
for name in "zohara-$CHANNEL.db.tar.gz" "zohara-$CHANNEL.files.tar.gz" "zohara-$CHANNEL.files" "zohara.db.tar.gz" "zohara.files.tar.gz" "zohara.files" \
            "zohara-$CHANNEL.db" "zohara.db"; do
  [ -f "$dir/$name" ] || continue
  echo "uploading $name"; put "$dir/$name" "$name"; up=$((up+1))
done

# The public copy must be byte-identical to what we built.
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
curl -fsS --retry 3 "$OCI_PUBLIC_BASE$prefix/zohara-$CHANNEL.db" -o "$tmp"
if [ "$(sha256sum < "$tmp")" != "$(sha256sum < "$dir/zohara-$CHANNEL.db")" ]; then
  echo "::error::the public zohara-$CHANNEL.db differs from the one just uploaded"; exit 1
fi
echo "OCI mirror ok: $up uploaded, $skipped already there; public zohara-$CHANNEL.db matches"
