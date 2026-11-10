#!/bin/sh
# Fetch the upstream sources the C program ports build from, each at the commit
# its patches were written against, into apps/ports/upstream/ (gitignored).
#
#   apps/ports/fetch.sh                  clone from the upstream hosts
#   MIRROR=<dir> apps/ports/fetch.sh     clone from local clones instead (<dir>/<name>,
#                                        klystron at <dir>/klystrack/klystron)
#
# Upstream is not vendored in this repo: the ports keep only their glue and
# patches (decisions.md, "C ports live in apps/ports"). Every checkout is
# verified against its pinned SHA, and binaryen's tarball against its sha256, so
# a rebuild compiles exactly the bytes the committed docs/demo-<tag>.wasm came
# from. A directory already at its pin is left alone; one at another commit is
# refused rather than silently rebuilt over.
set -eu
cd "$(dirname "$0")"
UP=upstream
mkdir -p "$UP"

# name  url  sha
PINS="
pt2-clone          https://github.com/8bitbubsy/pt2-clone.git        d42d5f100f0a6256ad0c085e5beeaa32cf1e8f63
grafX2             https://gitlab.com/GrafX2/grafX2.git              678a0f54ea7f3eeebc3fa4135213ea63f45a28bd
klystrack          https://github.com/kometbomb/klystrack.git        fe6e7465512bee32bf8e724857a7fbab902b8db0
klystrack/klystron https://github.com/kometbomb/klystron.git         10743245fbaf67fc02b432577dc4d47ad5e459da
chipnomad-tracker  https://github.com/Megus/chipnomad-tracker.git    e4b10d550fa19e3a00c95689450f0a3f542d5589
"
# klystron is klystrack's submodule; klystrack fe6e746 records exactly 10743245 for
# it, cloned here as a plain repo so MIRROR works the same for both.

checkout() { # checkout <name> <url> <sha>
    dir="$UP/$1" url=$2 sha=$3
    [ -n "${MIRROR:-}" ] && url="$MIRROR/$1"
    if [ -d "$dir/.git" ] || [ -f "$dir/.git" ]; then
        have=$(git -C "$dir" rev-parse HEAD)
        [ "$have" = "$sha" ] && { echo "  $1: at $sha"; return; }
        echo "fetch: $dir is at $have, not the pinned $sha: move it away and run again" >&2
        exit 1
    fi
    echo "  $1: $url @ $sha"
    rm -rf "$dir"
    git init -q "$dir"
    git -C "$dir" remote add origin "$url"
    # A fetch by SHA (GitHub and GitLab allow it); else the whole history.
    git -C "$dir" fetch -q --depth 1 origin "$sha" 2>/dev/null || git -C "$dir" fetch -q origin
    git -C "$dir" -c advice.detachedHead=false checkout -q "$sha"
    have=$(git -C "$dir" rev-parse HEAD)
    [ "$have" = "$sha" ] || { echo "fetch: $dir checked out $have, not $sha" >&2; exit 1; }
}

echo "$PINS" | while read -r name url sha; do
    if [ -n "$name" ]; then checkout "$name" "$url" "$sha"; fi
done

# SyncTERM (GPL-2.0) lives in Synchronet's whole tree (hundreds of MB of history): a shallow, blob-less,
# sparse checkout of the tag syncterm-1.9 takes only the directories the SyncTERM cart builds from.
SBBS_SHA=5bd319427e4f58cd965b056c69bb96ed47db7a81   # tag syncterm-1.9
SBBS_PATHS="/src/syncterm/ /src/conio/ /src/xpdev/ /src/comio/ /src/uifc/ /src/encode/ /src/hash/ /src/sbbs3/ /src/smblib/ /src/build/"
dir="$UP/sbbs" url=https://gitlab.synchro.net/main/sbbs.git
[ -n "${MIRROR:-}" ] && url="$MIRROR/sbbs"
if [ -d "$dir/.git" ]; then
    have=$(git -C "$dir" rev-parse HEAD)
    [ "$have" = "$SBBS_SHA" ] || { echo "fetch: $dir is at $have, not the pinned $SBBS_SHA: move it away and run again" >&2; exit 1; }
    echo "  sbbs: at $SBBS_SHA"
else
    echo "  sbbs: $url @ $SBBS_SHA (sparse: $SBBS_PATHS)"
    git init -q "$dir"
    git -C "$dir" remote add origin "$url"
    git -C "$dir" config core.sparseCheckout true
    printf '%s\n' $SBBS_PATHS > "$dir/.git/info/sparse-checkout"
    git -C "$dir" fetch -q --depth 1 --filter=blob:none origin "$SBBS_SHA"
    git -C "$dir" -c advice.detachedHead=false checkout -q "$SBBS_SHA"
    [ "$(git -C "$dir" rev-parse HEAD)" = "$SBBS_SHA" ] || { echo "fetch: $dir is not at $SBBS_SHA" >&2; exit 1; }
fi

# binaryen 132 (Apache-2.0), the npm build: wasm-opt as JavaScript, run with node.
# GrafX2, klystrack and SyncTERM are post-processed with its --asyncify.
BIN_SHA=6543555fb29bb92548f325c7dc18e9ab7dbb1215edda25993d1e3f71d85b8618
if [ -f "$UP/binaryen/package.json" ] && grep -q '"version": "132.0.0"' "$UP/binaryen/package.json"; then
    echo "  binaryen: 132.0.0"
else
    echo "  binaryen: npm binaryen@132.0.0"
    tgz="$UP/binaryen-132.0.0.tgz"
    curl -fsSL -o "$tgz" https://registry.npmjs.org/binaryen/-/binaryen-132.0.0.tgz
    echo "$BIN_SHA  $tgz" | sha256sum -c --quiet - || { echo "fetch: $tgz does not match its sha256" >&2; exit 1; }
    rm -rf "$UP/binaryen" && mkdir -p "$UP/binaryen"
    tar -xzf "$tgz" -C "$UP/binaryen" --strip-components=1
    rm -f "$tgz"
fi
echo "fetch: upstream ready in apps/ports/$UP"
