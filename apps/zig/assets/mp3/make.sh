#!/usr/bin/env bash
# The MP3 PLAYER's test files (apps/zig/assets/mp3/README.md): synthesised here, so CC0. Saw-wave
# chords, an arpeggio and noise hits (a dense spectrum, like a mixed track), encoded by LAME through
# ffmpeg's libmp3lame, with an ID3v2.3 title. Committed as encoded: the gate never re-encodes (an
# encoder upgrade would change every byte), this records how they were made.
#   apps/zig/assets/mp3/make.sh
set -euo pipefail
cd "$(dirname "$0")"
saw() { echo "(2*mod($1*t,1)-1)"; }
L="0.18*$(saw 110)+0.14*$(saw 138.59)+0.12*$(saw 164.81)+0.10*sin(2*PI*(440+220*floor(mod(8*t,4)))*t)+0.25*(random(0)-0.5)*exp(-18*mod(t,0.25))"
R="0.18*$(saw 110.5)+0.14*$(saw 146.83)+0.12*$(saw 174.61)+0.10*sin(2*PI*(660-110*floor(mod(8*t,4)))*t)+0.25*(random(1)-0.5)*exp(-18*mod(t+0.125,0.25))"
enc() { # <file> <rate> <channels> <kbps> <seconds> <title>
    ffmpeg -v error -y -f lavfi -i "aevalsrc='$L|$R':s=$2:d=$5" -ac "$3" -ar "$2" -c:a libmp3lame -b:a "$4k" \
        -write_xing 0 -id3v2_version 3 -write_id3v1 0 -metadata title="$6" "$1"
}
enc TONES44.MP3 44100 2 128 8 "Tones 44.1 kHz stereo"
enc TONES32.MP3 32000 2 96 4 "Tones 32 kHz stereo"
enc TONES48.MP3 48000 2 128 4 "Tones 48 kHz stereo"
enc MONO44.MP3 44100 1 64 4 "Tones 44.1 kHz mono"
ls -l ./*.MP3
