#!/usr/bin/env bash
# Offline test of scripts/upload-release.sh with a stand-in for gh: bash scripts/test-upload-release.sh
cd "$(dirname "$0")/.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; bad=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else bad=$((bad+1)); echo "FAIL: $1 (got $2, wanted $3)"; fi; }
# fake gh: records uploads in $T/log; "release view" lists what was uploaded; FAIL_ON makes uploads of a name fail
cat > "$T/gh" <<'G'
#!/usr/bin/env bash
if [ "$2" = upload ]; then
  shift 3; for a in "$@"; do case "$a" in --*) break;; esac; [ -n "${FAIL_ON:-}" ] && [ "$a" = "$FAIL_ON" ] && exit 1; echo "$a" >> "$T/log"; echo "$a" >> "$T/assets"; done; exit 0
fi
[ "$2" = view ] && { cat "$T/assets" 2>/dev/null; exit 0; }
G
chmod +x "$T/gh"; export T GH="$T/gh" UPLOAD_RETRY_SLEEP=0
mk() { rm -rf "$T/repo" "$T/in" "$T/log" "$T/assets"; mkdir "$T/repo" "$T/in"
  for f in zohara-new-1-1-x86_64.pkg.tar.zst zohara-old-1-1-x86_64.pkg.tar.zst zohara.db zohara.db.tar.gz zohara.files zohara-alpha.files zohara-alpha.db.tar.gz zohara-alpha.db; do echo x > "$T/repo/$f"; done
  cp "$T/repo/zohara-new-1-1-x86_64.pkg.tar.zst" "$T/in/"; }

mk; bash scripts/upload-release.sh channel-alpha o/r alpha "$T/repo" "$T/in" >/dev/null 2>&1; ok "normal run exits 0" "$?" 0
ok "new package is uploaded first" "$(head -1 "$T/log")" "zohara-new-1-1-x86_64.pkg.tar.zst"
ok "channel database is uploaded last" "$(tail -1 "$T/log")" "zohara-alpha.db"
ok "old package goes before any database" "$(grep -n 'old' "$T/log" | cut -d: -f1 | head -1 | awk '{print ($1<4)}')" 1

# the package upload fails: the database must not be touched at all
mk; FAIL_ON=zohara-new-1-1-x86_64.pkg.tar.zst bash scripts/upload-release.sh channel-alpha o/r alpha "$T/repo" "$T/in" >/dev/null 2>&1; ok "failed package upload exits non-zero" "$?" 1
ok "no database uploaded after a failed package" "$( [ -f "$T/log" ] && grep -c 'db\|files' "$T/log" || echo 0)" 0

# upload "succeeds" but GitHub does not list the package: stop before the database
mk; cat > "$T/gh2" <<'G'
#!/usr/bin/env bash
[ "$2" = upload ] && { echo "$@" >> "$T/log"; exit 0; }
exit 0
G
chmod +x "$T/gh2"; GH="$T/gh2" bash scripts/upload-release.sh channel-alpha o/r alpha "$T/repo" "$T/in" >/dev/null 2>&1; ok "unlisted package stops the publish" "$?" 1
ok "only the package was sent" "$(wc -l < "$T/log")" 1

# a database upload failing last leaves everything else uploaded
mk; FAIL_ON=zohara-alpha.db bash scripts/upload-release.sh channel-alpha o/r alpha "$T/repo" "$T/in" >/dev/null 2>&1; ok "failed channel db exits non-zero" "$?" 1
ok "packages were already up" "$(grep -c pkg.tar.zst "$T/log")" 2

echo "upload-release: $pass passed, $bad failed"; [ "$bad" = 0 ]
