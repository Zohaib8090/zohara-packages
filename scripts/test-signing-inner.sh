#!/usr/bin/env bash
# Runs inside the container started by test-signing.sh.
set -uo pipefail
pass=0; fail=0
ok()   { pass=$((pass+1)); echo "ok   - $1"; }
bad()  { fail=$((fail+1)); echo "FAIL - $1"; }
expect_ok()   { local d="$1"; shift; if "$@" >/tmp/out 2>&1; then ok "$d"; else bad "$d (should have worked)"; sed 's/^/       /' /tmp/out | tail -5; fi; }
expect_fail() { local d="$1"; shift; if "$@" >/tmp/out 2>&1; then bad "$d (should have been refused)"; else ok "$d  [$(grep -iE "error|invalid|unknown|signature" /tmp/out | tail -1 | cut -c1-110)]"; fi; }

pacman -Sy --noconfirm --needed base-devel gnupg >/dev/null 2>&1
id b >/dev/null 2>&1 || useradd -m b

# ── tiny test packages ──
mkpkg() { # NAME VERSION DESTDIR
  local d; d="$(mktemp -d)"; chown b "$d"; mkdir -p "$3"
  cat > "$d/PKGBUILD" <<PK
pkgname=$1
pkgver=$2
pkgrel=1
pkgdesc='signing test'
arch=(any)
license=(MIT)
package() { install -Dm644 /dev/null "\$pkgdir/usr/share/$1/ok"; }
PK
  ( cd "$d" && su b -c "PKGDEST=$d makepkg -f --nodeps" >/dev/null 2>&1 ) && cp "$d"/*.pkg.tar.zst "$3"/
}
mkdir -p /srv; for r in signed unsigned impostor tampered; do rm -rf /srv/$r; mkpkg ztest-a 1.0 /srv/$r; mkpkg ztest-b 2.0 /srv/$r; done
[ "$(ls /srv/signed/*.pkg.tar.zst | wc -l)" = 2 ] && ok "test packages built" || { bad "test packages built"; exit 1; }

# ── two keys: the "Zohara" one and an impostor ──
genkey() { GNUPGHOME="$1" gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key "$2" ed25519 sign 1y >/dev/null 2>&1; GNUPGHOME="$1" gpg --with-colons --list-keys | awk -F: '/^fpr/{print $10; exit}'; }
mkdir -m700 /tmp/k1 /tmp/k2
FPR1="$(genkey /tmp/k1 'Zohara test <z@test.invalid>')"; FPR2="$(genkey /tmp/k2 'Impostor <i@test.invalid>')"
SECRET1="$(GNUPGHOME=/tmp/k1 gpg --armor --export-secret-keys "$FPR1")"; SECRET2="$(GNUPGHOME=/tmp/k2 gpg --armor --export-secret-keys "$FPR2")"
GNUPGHOME=/tmp/k1 gpg --armor --export "$FPR1" > /tmp/zohara.pub
printf '%s\n' "$FPR1" > /tmp/pinned.fpr

BR=/w/scripts/build-repo.sh
# signed with the right key
ZOHARA_PKG_SIGNING_KEY="$SECRET1" PINNED_FPR_FILE=/tmp/pinned.fpr bash $BR /srv/signed stable >/tmp/out 2>&1 && ok "build-repo signs with the pinned key" || { bad "build-repo signs with the pinned key"; tail -5 /tmp/out; }
[ -e /srv/signed/zohara-stable.db.sig ] && [ -e /srv/signed/ztest-a-1.0-1-any.pkg.tar.zst.sig ] && ok "database and package signatures exist" || bad "database and package signatures exist"
# a key that is not the pinned one is refused before anything is signed
ZOHARA_PKG_SIGNING_KEY="$SECRET2" PINNED_FPR_FILE=/tmp/pinned.fpr bash $BR /srv/impostor stable >/dev/null 2>&1 && bad "a swapped key is refused" || ok "a swapped key is refused by build-repo"
# no key at all: unsigned, as before
env -u ZOHARA_PKG_SIGNING_KEY bash $BR /srv/unsigned stable >/dev/null 2>&1 && [ ! -e /srv/unsigned/zohara-stable.db.sig ] && ok "without a key the repository is built unsigned" || bad "without a key the repository is built unsigned"
# the impostor's repository, signed by a key nobody trusts (no pin, so build-repo allows it)
ZOHARA_PKG_SIGNING_KEY="$SECRET2" PINNED_FPR_FILE=/nonexistent bash $BR /srv/impostor stable >/dev/null 2>&1 || bad "impostor repo built"
# a repository whose package was changed after signing
cp -r /srv/signed/. /srv/tampered/; printf 'x' >> /srv/tampered/ztest-a-1.0-1-any.pkg.tar.zst

# ── pacman, strict mode, that trusts only the Zohara key ──
mkdir -p /tmp/gpg /tmp/root /tmp/db /tmp/cache; chmod 700 /tmp/gpg
conf() { cat > /tmp/pacman.conf <<C
[options]
RootDir = /tmp/root
DBPath = /tmp/db
CacheDir = /tmp/cache
GPGDir = /tmp/gpg
LogFile = /tmp/pacman.log
Architecture = auto
SigLevel = Required DatabaseRequired
[zohara-stable]
SigLevel = Required DatabaseRequired
Server = file://$1
C
}
conf /srv/signed
pacman-key --config /tmp/pacman.conf --gpgdir /tmp/gpg --init >/dev/null 2>&1
pacman-key --config /tmp/pacman.conf --gpgdir /tmp/gpg --add /tmp/zohara.pub >/dev/null 2>&1
pacman-key --config /tmp/pacman.conf --gpgdir /tmp/gpg --lsign-key "$FPR1" >/dev/null 2>&1
[ -n "$(gpg --homedir /tmp/gpg --list-keys "$FPR1" 2>/dev/null)" ] && ok "the Zohara key is in the test keyring" || bad "the Zohara key is in the test keyring"
P="pacman --config /tmp/pacman.conf --noconfirm"
fresh() { rm -rf /tmp/db/* /tmp/root/* /tmp/cache/*; mkdir -p /tmp/db/local; conf "$1"; }

fresh /srv/signed;     expect_ok   "pacman (strict) accepts the signed repository"        $P -Sy
expect_ok   "pacman (strict) installs a signed package"                                  $P -S ztest-a ztest-b
fresh /srv/unsigned;   expect_fail "pacman (strict) refuses an unsigned repository"       $P -Sy
fresh /srv/impostor;   expect_fail "pacman (strict) refuses a repository signed by an unknown key" $P -Sy
fresh /srv/tampered;   $P -Sy >/dev/null 2>&1
expect_fail "pacman (strict) refuses a package changed after signing"                    $P -S ztest-a
# the old setting still works with a signed repository once the key is known
sed -i 's/^SigLevel = Required DatabaseRequired$/SigLevel = Optional TrustAll/' /tmp/pacman.conf
fresh /srv/signed; sed -i 's/^SigLevel = Required DatabaseRequired$/SigLevel = Optional TrustAll/' /tmp/pacman.conf
expect_ok   "the old Optional TrustAll setting still accepts a signed repository (key known)" $P -Sy

# THE ROLLOUT HAZARD: a machine on the old setting that does not have the key yet. Signing before the key is
# installed there breaks its updates, so the key package must reach machines first.
mkdir -p /tmp/gpg2 && chmod 700 /tmp/gpg2
fresh /srv/signed; sed -i 's/^SigLevel = Required DatabaseRequired$/SigLevel = Optional TrustAll/; s#^GPGDir = .*#GPGDir = /tmp/gpg2#' /tmp/pacman.conf
pacman-key --config /tmp/pacman.conf --gpgdir /tmp/gpg2 --init >/dev/null 2>&1
expect_fail "a machine WITHOUT the key breaks on a signed repository (so ship the key first)" $P -Sy

echo; echo "passed $pass, failed $fail"; [ "$fail" = 0 ]
