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
if [ "${KIND:-}" = "iso" ]; then
  # The ISO build also starts from repository_dispatch (a new settings build); pull requests never.
  case "$event" in push|workflow_dispatch|repository_dispatch) ;; *) fail "run $RUN_ID was started by '$event'";; esac
  [ "$(check .name)" = "Build Zohara OS ISO" ] || fail "run $RUN_ID is '$(check .name)', not an ISO build"
  [ "$(check .head_branch)" = "master" ] || fail "an ISO can only be promoted from a master build (this one is '$(check .head_branch)')"
  head_repo="$(check '.head_repository.full_name // ""')"
  [ "${head_repo,,}" = "${SRC_REPO,,}" ] || fail "run $RUN_ID does not come from $SRC_REPO itself"
  echo "iso run ok: $SRC_REPO #$RUN_ID ($event on master, $(check .head_sha | cut -c1-7))"; exit 0
fi
case "$event" in push|workflow_dispatch) ;; *) fail "run $RUN_ID was started by '$event'; only push or manual runs can be published";; esac
head_repo="$(check '.head_repository.full_name // ""')"
[ "${head_repo,,}" = "${SRC_REPO,,}" ] || fail "run $RUN_ID does not come from $SRC_REPO itself (it comes from '$head_repo')"
branch="$(check .head_branch)"
if [ "${SRC_REPO,,}" = "zohaib8090/zohara" ]; then
  # The main repository: only its package workflows count (its ISO builds are promoted by promote-iso.yml), and
  # its default branch is master.
  case "$(check .name)" in
    "Build & Publish Zohara Store"|"Build & Publish Zohara Snapshots"|"Build & Publish Zohara Voice"|"Build & Publish Zohara Welcome"|"Build & Publish Zohara Keyring") ;;
    *) fail "run $RUN_ID is '$(check .name)', not one of the package builds";;
  esac
  [ "$branch" = master ] || fail "a run from branch '$branch' cannot be published (packages come from master here)"
else
  case "$CHANNEL:$branch" in
    stable:main|beta:beta|beta:main|alpha:main|alpha:beta) ;;
    *) fail "a run from branch '$branch' cannot be published to the $CHANNEL channel";;
  esac
fi
echo "run ok: $SRC_REPO #$RUN_ID ($event on $branch, $(check .head_sha | cut -c1-7))"
