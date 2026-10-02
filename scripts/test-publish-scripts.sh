#!/usr/bin/env bash
# Offline tests for the publish helper scripts: bash scripts/test-publish-scripts.sh [path/to/some.pkg.tar.zst]
cd "$(dirname "$0")/.."
pass=0; bad=0
t() { # t "name" expected_exit command...
  local name="$1" want="$2"; shift 2
  if "$@" >/dev/null 2>&1; then got=0; else got=1; fi
  if [ "$got" = "$want" ]; then pass=$((pass+1)); else bad=$((bad+1)); echo "FAIL: $name (exit $got, wanted $want)"; fi
}
V() { env -i PATH="$PATH" "$@" bash scripts/validate-publish-inputs.sh; }
good="CHANNEL=stable SRC_REPO=Zohaib8090/zohara-settings RUN_ID=123"
t "good stable"                    0 V $good
t "good alpha apps + hints"        0 V CHANNEL=alpha SRC_REPO=Zohaib8090/zohara-apps RUN_ID=9 ARTIFACT_NAME=zohara-apps-arch PKG_FILENAME=zohara-voice-1.9.4-1-x86_64.pkg.tar.zst PKG=zohara-voice VER=1.9.4
t "bad channel"                    1 V CHANNEL=prod SRC_REPO=Zohaib8090/zohara-settings RUN_ID=1
t "empty channel"                  1 V SRC_REPO=Zohaib8090/zohara-settings RUN_ID=1
t "other owner"                    1 V CHANNEL=stable SRC_REPO=attacker/zohara-settings RUN_ID=1
t "other repo"                     1 V CHANNEL=stable SRC_REPO=Zohaib8090/zohara-website RUN_ID=1
t "case trick on repo"             1 V CHANNEL=stable SRC_REPO=zohaib8090/Zohara-Settings RUN_ID=1
t "run id letters"                 1 V CHANNEL=stable SRC_REPO=Zohaib8090/zohara-settings RUN_ID=12a
t "run id injection"               1 V CHANNEL=stable SRC_REPO=Zohaib8090/zohara-settings 'RUN_ID=1; rm -rf /'
t "artifact with slash"            1 V $good ARTIFACT_NAME=../x
t "artifact with space"            1 V $good 'ARTIFACT_NAME=a b'
t "pkg file not pkg"               1 V $good PKG_FILENAME=evil.sh
t "pkg file with path"             1 V $good PKG_FILENAME=../a.pkg.tar.zst
t "pkg name shell chars"           1 V $good 'PKG=a$(id)'
t "version shell chars"            1 V $good 'VER=1;id'
if [ -n "${1:-}" ]; then
  out="$(bash scripts/read-pkginfo.sh "$1" 2>&1)"; [ $? = 0 ] && [[ "$out" =~ ^[a-z0-9@._+-]+\ [A-Za-z0-9._+:~-]+$ ]] && pass=$((pass+1)) || { bad=$((bad+1)); echo "FAIL: read-pkginfo on $1 -> $out"; }
fi
t "pkginfo on a non-package"       1 bash scripts/read-pkginfo.sh scripts/read-pkginfo.sh
echo "passed $pass, failed $bad"; [ "$bad" = 0 ]
