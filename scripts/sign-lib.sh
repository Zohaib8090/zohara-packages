#!/usr/bin/env bash
# Signing helpers, sourced by build-repo.sh. The signing key arrives as the environment variable
# ZOHARA_PKG_SIGNING_KEY (an ASCII-armored secret key, from a GitHub Actions secret) and is imported into a private
# temporary keyring that is deleted when the shell exits. The key is never written anywhere else or printed.
#
# After signing_setup:  SIGNING=1, GPGKEY=<fingerprint>   (a key was given and is the pinned one)
#                       SIGNING=0                           (no key was given: publish unsigned, as before)
# A key that is not the pinned one (signing-key.fpr in this repository) stops the publish: a swapped secret must
# never silently sign packages that machines would then trust.

signing_setup() {
  SIGNING=0
  [ -n "${ZOHARA_PKG_SIGNING_KEY:-}" ] || return 0
  GNUPGHOME="$(mktemp -d)"; export GNUPGHOME; chmod 700 "$GNUPGHOME"
  trap 'gpgconf --kill gpg-agent >/dev/null 2>&1 || true; rm -rf "$GNUPGHOME"' EXIT
  printf '%s\n' "$ZOHARA_PKG_SIGNING_KEY" | gpg --batch --quiet --import >/dev/null 2>&1 \
    || { echo "::error::the signing key secret could not be imported"; return 1; }
  GPGKEY="$(gpg --batch --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^fpr/{print $10; exit}')"
  [ -n "$GPGKEY" ] || { echo "::error::no secret key found in the signing key secret"; return 1; }
  local pinned_file="${PINNED_FPR_FILE:-$(dirname "${BASH_SOURCE[0]}")/../signing-key.fpr}"
  if [ -f "$pinned_file" ]; then
    local pinned; pinned="$(tr -d ' \n\r' < "$pinned_file")"
    [ "$GPGKEY" = "$pinned" ] || { echo "::error::the signing key is not the pinned one (got ${GPGKEY: -16}, expected ${pinned: -16})"; return 1; }
  fi
  SIGNING=1
  echo "signing with key ...${GPGKEY: -16}"
}

# Signs every package in DIR that has no .sig yet (older packages in a release get theirs the first time).
sign_missing_packages() {
  local dir="$1" f n=0
  for f in "$dir"/*.pkg.tar.zst; do
    [ -e "$f" ] || continue
    [ -e "$f.sig" ] && continue
    gpg --batch --yes --quiet --detach-sign --no-armor -u "$GPGKEY" -o "$f.sig" "$f"
    n=$((n+1))
  done
  echo "signed $n package(s)"
}
