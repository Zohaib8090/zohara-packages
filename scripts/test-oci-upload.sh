#!/usr/bin/env bash
# Offline test of scripts/oci-upload.sh against a local fake bucket (python3 + curl + jq needed).
cd "$(dirname "$0")/.."
set -u
T="$(mktemp -d)"; PORT=$((20000 + RANDOM % 20000)); bad=0; pass=0
python3 scripts/fake-oci-server.py "$PORT" "$T/bucket" & SPID=$!
trap 'kill $SPID 2>/dev/null; rm -rf "$T"' EXIT
for _ in $(seq 1 30); do curl -s -o /dev/null "http://127.0.0.1:$PORT/pub/x" && break; sleep 0.2; done
export OCI_PACKAGES_PAR="http://127.0.0.1:$PORT/par/o/" OCI_PUBLIC_BASE="http://127.0.0.1:$PORT/pub/o/" CHANNEL=alpha
# the fake maps /par/<rest> -> bucket/<rest>, so objects land in bucket/o/<prefix>/<name>
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else bad=$((bad+1)); echo "FAIL: $1 (got '$2', wanted '$3')"; fi; }
mkdir -p "$T/repo"; cd "$T/repo"
head -c 3000 /dev/urandom > zohara-welcome-0.1.0-1-x86_64.pkg.tar.zst
head -c 5000 /dev/urandom > zohara-update-0.1.0-1-x86_64.pkg.tar.zst
echo db1 > zohara-alpha.db.tar.gz; cp zohara-alpha.db.tar.gz zohara-alpha.db; cp zohara-alpha.db zohara.db
cd - >/dev/null
bash scripts/oci-upload.sh channel-alpha "$T/repo" >"$T/out1" 2>&1; ok "first run exits 0" "$?" 0
grep -q "2 uploaded\|4 uploaded\|5 uploaded\|6 uploaded" "$T/out1"; ok "first run uploads" "$?" 0
ok "package stored" "$(ls "$T/bucket/o/channel-alpha" | grep -c pkg.tar.zst)" 2
ok "db stored" "$(cat "$T/bucket/o/channel-alpha/zohara-alpha.db")" db1
bash scripts/oci-upload.sh channel-alpha "$T/repo" >"$T/out2" 2>&1; ok "second run exits 0" "$?" 0
grep -q "2 already there" "$T/out2"; ok "second run skips unchanged packages" "$?" 0
echo db2 > "$T/repo/zohara-alpha.db"
bash scripts/oci-upload.sh channel-alpha "$T/repo" >"$T/out3" 2>&1; ok "changed db exits 0" "$?" 0
ok "db replaced" "$(cat "$T/bucket/o/channel-alpha/zohara-alpha.db")" db2
# a public copy that differs must be reported (simulate by making the write go elsewhere)
echo db3 > "$T/repo/zohara-alpha.db"
OCI_PACKAGES_PAR="http://127.0.0.1:$PORT/par/elsewhere/o/" bash scripts/oci-upload.sh channel-alpha "$T/repo" >"$T/out4" 2>&1; ok "mismatch is caught" "$?" 1
OCI_PACKAGES_PAR="http://127.0.0.1:$PORT/par/o" bash scripts/oci-upload.sh channel-alpha "$T/repo" >"$T/out5" 2>&1; ok "address without /o/ refused" "$?" 1
bash scripts/oci-upload.sh '../x' "$T/repo" >"$T/out6" 2>&1; ok "bad prefix refused" "$?" 1
env -u OCI_PACKAGES_PAR bash scripts/oci-upload.sh channel-alpha "$T/repo" >"$T/out7" 2>&1; ok "missing PAR refused" "$?" 1
echo "passed $pass, failed $bad"; [ "$bad" = 0 ]
