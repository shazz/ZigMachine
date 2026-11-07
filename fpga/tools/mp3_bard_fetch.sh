#!/usr/bin/env bash
# Fetch the third-party MP3 decoders the BARD MP3 study (fpga/review/MP3_BARD_STUDY.md) measured into
# prototypes/mp3_bard_re/src/ (gitignored): their licences (RPSL/RCSL) are not ours to commit.
#   tools/mp3_bard_fetch.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
D="$ROOT/prototypes/mp3_bard_re/src"
fetch() { # <dir> <owner/repo> <commit>
    [ -d "$D/$1" ] && return
    mkdir -p "$D/$1"
    curl -sfL "https://codeload.github"".com/$2/tar.gz/$3" | tar xz -C "$D/$1" --strip-components=1
}
fetch helix chmorgan/libhelix-mp3 "${HELIX_REV:-fb0c06b5cb964c50706c08b0c3bc6615f08d0ffe}"
fetch lef Lefucjusz/Helix-MP3-Decoder "${LEF_REV:-e4f5adadb5126708144e55a862f59e318cbffb51}"
# PacketVideo's pvmp3 (Apache-2.0), as AOSP carries it
if [ ! -d "$D/pvmp3" ]; then
    mkdir -p "$D/pvmp3"
    curl -sfL "https://android.googlesource.com/platform/frameworks/av/+archive/${PV_REV:-e2f098935447ca4945946de5cb69db843fe3f003}/media/module/codecs/mp3dec.tar.gz" | tar xz -C "$D/pvmp3"
fi
ls "$D"
