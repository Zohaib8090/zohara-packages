#!/usr/bin/env bash
# End-to-end test of package signing in a throwaway Arch container (needs docker). It builds a repository with
# scripts/build-repo.sh and then asks the real pacman, set to the strictest mode (SigLevel = Required
# DatabaseRequired), whether it accepts it. A throwaway key stands in for Zohara's real one, which is never used here.
#   bash scripts/test-signing.sh
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec docker run --rm -v "$here":/w:ro archlinux:latest bash /w/scripts/test-signing-inner.sh
