#!/usr/bin/env bash
# Checks the inputs of a publish BEFORE anything is downloaded or uploaded. Pure text checks, no network, so
# scripts/test-publish-scripts.sh can run it anywhere. Values arrive as environment variables (never pasted
# into a script by the workflow), so a crafted value cannot turn into shell code.
#
#   CHANNEL        stable | beta | alpha
#   SRC_REPO       must be one of the allowed source repositories below
#   RUN_ID         digits only
#   ARTIFACT_NAME  optional, plain file-name characters
#   PKG_FILENAME   optional, plain file-name characters, must end in .pkg.tar.zst
#   PKG, VER       optional (the package name and version are read from the package itself; if given they must match)
set -euo pipefail

# Zohaib8090/zohara also builds the Store, Snapshots, Voice and Welcome packages; verify-source-run.sh then insists
# the run is one of those package workflows on master (the same repo also builds the ISO).
ALLOWED_SOURCES=(Zohaib8090/zohara-settings Zohaib8090/zohara-apps Zohaib8090/zohara Zohaib8090/zohara-link)

fail() { echo "::error::$*"; exit 1; }

# KIND=iso: promoting a finished ISO build from the zohara repository (see promote-iso.yml). No channel there.
if [ "${KIND:-}" = "iso" ]; then
  [ "${SRC_REPO:-}" = "Zohaib8090/zohara" ] || fail "an ISO can only be promoted from Zohaib8090/zohara (got '${SRC_REPO:-}')"
  [[ "${RUN_ID:-}" =~ ^[0-9]+$ ]] || fail "run id must be digits only (got '${RUN_ID:-}')"
  echo "inputs ok: iso run=$RUN_ID"; exit 0
fi

case "${CHANNEL:-}" in stable|beta|alpha) ;; *) fail "channel must be stable, beta or alpha (got '${CHANNEL:-}')";; esac

ok=0
for r in "${ALLOWED_SOURCES[@]}"; do [ "${SRC_REPO:-}" = "$r" ] && ok=1; done
[ "$ok" = 1 ] || fail "source repository '${SRC_REPO:-}' is not on the allowed list: ${ALLOWED_SOURCES[*]}"

[[ "${RUN_ID:-}" =~ ^[0-9]+$ ]] || fail "run id must be digits only (got '${RUN_ID:-}')"

safe_name='^[A-Za-z0-9@._+:~-]+$'
if [ -n "${ARTIFACT_NAME:-}" ]; then [[ "$ARTIFACT_NAME" =~ $safe_name ]] || fail "artifact name has characters that are not allowed"; fi
if [ -n "${PKG_FILENAME:-}" ]; then
  [[ "$PKG_FILENAME" =~ $safe_name ]] || fail "package file name has characters that are not allowed"
  [[ "$PKG_FILENAME" == *.pkg.tar.zst ]] || fail "package file name must end in .pkg.tar.zst"
fi
if [ -n "${PKG:-}" ]; then [[ "$PKG" =~ ^[a-z0-9@._+-]+$ ]] || fail "package name has characters that are not allowed"; fi
if [ -n "${VER:-}" ]; then [[ "$VER" =~ ^[A-Za-z0-9._+:~-]+$ ]] || fail "version has characters that are not allowed"; fi
echo "inputs ok: channel=$CHANNEL source=$SRC_REPO run=$RUN_ID"
