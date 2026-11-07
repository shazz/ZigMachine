#!/usr/bin/env bash
# The BARD SID study (fpga/review/SID_BARD_STUDY.md): fetch cRSID 1.58 (Hermit, WTF licence) and the
# six study tunes from HVSC into prototypes/sid_re/ (git-ignored: the tunes are never committed).
#   tools/sid_bard_fetch.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
P="$ROOT/prototypes/sid_re"
mkdir -p "$P/dl" "$P/src" "$P/tunes"
if [ ! -d "$P/src/cRSID-1.58" ]; then
    curl -sfL -o "$P/dl/crsid158.tgz" "https://csdb.dk/getinternalfile.php/279277/cRSID-1.58-with-source-code.tar.gz"
    tar -xzf "$P/dl/crsid158.tgz" -C "$P/src"
fi
HVSC=https://hvsc.brona.dk/HVSC/C64Music/MUSICIANS
for t in H/Hubbard_Rob/Commando T/Tel_Jeroen/Cybernoid_II J/Jammer/Club_Style G/Galway_Martin/Arkanoid \
    M/Mahoney/Storebror G/Galway_Martin/Wizball; do
    f="$P/tunes/$(basename "$t").sid"
    [ -s "$f" ] || curl -sfL -o "$f" "$HVSC/$t.sid"
done
# The study's tune list: <file> <subtune, 0 = the header's default> <what it covers>
cat >"$P/tunes.list" <<'EOF'
Commando.sid 1 classic-1x-Hubbard
Cybernoid_II.sid 1 6581-filter-every-frame
Club_Style.sid 1 8580-filter
Arkanoid.sid 1 RSID-digi-Galway
Storebror.sid 1 RSID-NMI-digi-filter-worst
Wizball.sid 4 4x-CIA-Galway
EOF
ls -l "$P/tunes"
