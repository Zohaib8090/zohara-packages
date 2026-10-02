#!/usr/bin/env bash
# Asks GitHub about the source run and refuses anything that should never reach users:
# a run that did not succeed, was started by a pull request, belongs to another repository, or is on a branch
# that does not match the channel (stable only from main; beta from beta or main; alpha from either).
# Needs GH_TOKEN, SRC_REPO, RUN_ID and CHANNEL.
set -euo pipefail
fail() { echo "::error::$*"; exit 1; }

run_json="$(gh api "repos/$SRC_REPO/actions/runs/$RUN_ID")" || fail "could not read run $RUN_ID of $SRC_REPO"
check() { jq -r "$1" <<<"$run_json"; }

[ "$(check .status)" = completed ] && [ "$(check .conclusion)" = success ] || fail "run $RUN_ID did not finish successfully"
event="$(check .event)"
case "$event" in push|workflow_dispatch) ;; *) fail "run $RUN_ID was started by '$event'; only push or manual runs can be published";; esac
head_repo="$(check '.head_repository.full_name // ""')"
[ "${head_repo,,}" = "${SRC_REPO,,}" ] || fail "run $RUN_ID does not come from $SRC_REPO itself (it comes from '$head_repo')"
branch="$(check .head_branch)"
case "$CHANNEL:$branch" in
  stable:main|beta:beta|beta:main|alpha:main|alpha:beta) ;;
  *) fail "a run from branch '$branch' cannot be published to the $CHANNEL channel";;
esac
echo "run ok: $SRC_REPO #$RUN_ID ($event on $branch, $(check .head_sha | cut -c1-7))"
