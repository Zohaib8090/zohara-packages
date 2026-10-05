# Package signing

Goal: a machine installs a Zohara package only if it was signed with the Zohara key, so someone who can write to the
GitHub release (or the OCI bucket, or sits in the middle of a download) cannot put code on machines. Until this is
finished, machines still use `SigLevel = Optional TrustAll` for `[zohara-stable]` and accept anything.

## The pieces

| Piece | Where | State (2026-10-05) |
|---|---|---|
| Signing key (ed25519, expires 2031-10-04) | secret half on the owner's laptop, `~/.zohara-signing/` (**not in git**); public half `zohara-packages-signing-key.asc` here | made |
| Pinned fingerprint `A08F86264C0C384F567697A949D285AF8166C18D` | `signing-key.fpr` here | pinned |
| `scripts/sign-lib.sh`, `scripts/build-repo.sh` | sign every package and the database when the secret `ZOHARA_PKG_SIGNING_KEY` exists; refuse a key that is not the pinned one | in use by `publish.yml`; **signing is off** until the secret is added |
| `scripts/oci-upload.sh` | mirrors the `.sig` files too | done |
| `zohara-keyring` package | repo `Zohaib8090/zohara`, folder `zohara-keyring/`; installs and trusts the public key | **published to stable** |
| Machines require signatures (`SigLevel = Required DatabaseRequired`) | `/etc/pacman.conf`, `[zohara-*]` sections | not yet |

## Tests

* `bash scripts/test-signing.sh` (needs docker): 13 checks against the real pacman with a throwaway key: signed repo
  accepted, unsigned / wrong key / changed package refused, and a machine **without** the key breaks on a signed repo.
* `bash ../zohara/zohara-keyring/test-e2e.sh` (needs docker and the secret key): the whole chain with the real key:
  no key -> refused, keyring package installed -> signed repo accepted, unsigned repo still refused.

## Rollout order (do not skip steps)

A signed repository **breaks** every machine that does not have the key yet (the test above proves it: "unknown
key"). So:

1. **Publish `zohara-keyring`.** Done. Machines get it with their next update from the Store.
2. **Wait until the machines that matter have it** (`pacman -Q zohara-keyring`, or Store > Updates).
3. **Add the secret.** GitHub > `zohara-packages` > Settings > Secrets and variables > Actions > New repository
   secret, name `ZOHARA_PKG_SIGNING_KEY`, value = the whole contents of `~/.zohara-signing/zohara-packages-secret.asc`
   (the owner pastes it; nobody else should). The next publish of any package signs **every** package in that
   channel's release and the database.
4. **Switch machines to `Required`.** Change `[zohara-stable]` to `SigLevel = Required DatabaseRequired` (a later
   `zohara-keyring` version, and `customize_airootfs.sh` for new installs). Add `zohara-keyring` to the ISO.
5. Unsigned packages are then refused. Test on one machine first (`sudo pacman -Syu`).

## Key care

* Back up `~/.zohara-signing/` (the secret key and `gnupg/openpgp-revocs.d/*.rev`, the revocation certificate) to a
  USB stick that is not the laptop. Losing the secret key means a new key and a new keyring package for every machine.
* The secret in GitHub can sign anything, so anyone who can edit that repository's Actions can misuse it. A stronger
  setup keeps the key offline and signs by hand or from the admin site (plan phase 4).
* The key expires 2031-10-04. Renew or replace it before then: bump `pkgver` of `zohara-keyring`, update
  `zohara-trusted` / `zohara-revoked`, and `signing-key.fpr`.
* To revoke: put the old fingerprint in `zohara-revoked`, publish a new `zohara-keyring`.
