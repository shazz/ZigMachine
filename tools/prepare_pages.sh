#!/bin/sh
# Prepare the GitHub Pages site (site/) from source: every cart, every disk and
# the channel list the front page's +/- buttons step through.
#
# WHY THIS EXISTS: site/ is what GitHub Pages serves, and it is BUILD OUTPUT
# committed to git. A source change pushed without its rebuilt cart, disk or
# channels.json deploys a page that runs the old screen, or lists one with no
# disk. Nothing failed; the site was just quietly wrong.
#
#   tools/prepare_pages.sh            rebuild site/ (carts, disks, channels.json)
#   tools/prepare_pages.sh --check    rebuild, then FAIL if site/ now differs from
#                                     what git has: the regenerated files were
#                                     not committed (used by .githooks)
#
# It is the fast half of ./build.sh: no native tests and no headless harnesses.
# Those stay in ./build.sh, which the pre-push hook runs in full.
set -e
cd "$(dirname "$0")/.."
[ -d "$HOME/.local/zig/0.16.0" ] && PATH="$HOME/.local/zig/0.16.0:$PATH"

CHECK=""
[ "$1" = "--check" ] && CHECK=1

zig build -Drelease=true -Dwasm
tools/mkdisks.sh
python3 tools/channels.py
python3 tools/channels.py --check
node apps/harness/disk_check.mjs > /dev/null

[ -z "$CHECK" ] && { echo "pages: site/ rebuilt"; exit 0; }

stale=$(git status --porcelain -- site)
if [ -n "$stale" ]; then
    echo "pages: site/ is out of date with the source. Rebuilt files not in git:"
    echo "$stale" | sed 's/^/    /'
    echo "Stage and commit them (git add site/...), then try again."
    exit 1
fi
echo "pages: site/ matches the source ✅"
