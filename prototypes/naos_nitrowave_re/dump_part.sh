#!/bin/sh
# dump_part.sh N PC OUT VBL [VBL...] -- boot NITROWAV.ST, start part F<N> at
# VBL 1400 (as run_part.sh); for each VBL given, the first time PC is reached
# with Hatari's VBL counter EQUAL to it, save the 512 KB of RAM to OUT.<VBL>.
# (`VBL > X` instead of `=` for the first one: use FIRST=gt.) The debugger's
# status lines go to OUT.log ("CPU=$..., VBL=...").
set -e
cd "$(dirname "$0")"
N=$1; PC=$2; OUT=$3; shift 3
case $N in 1) T='$b6 $04' ;; 2) T='$b6 $0e' ;; 3) T='$b6 $18' ;; esac
mkdir -p dbg
printf 'b VBL = 1400 :once :file %s/dbg/jmp%s.ini\n' "$PWD" "$N" > dbg/dump.ini
printf 'w $AFD6 $4e $f9 $00 $00 %s\n' "$T" > "dbg/jmp$N.ini"
LAST=0
for v in "$@"; do
  op='='; [ "${FIRST:-}" = gt ] && [ "$LAST" = 0 ] && op='>'
  printf 'b pc = %s && VBL %s %s :once :file %s/dbg/save%s.ini\n' "$PC" "$op" "$v" "$PWD" "$v" >> "dbg/jmp$N.ini"
  printf 'savebin %s/%s.%s 0 $80000\nr\nc\n' "$PWD" "$OUT" "$v" > "dbg/save$v.ini"
  LAST=$v
done
printf 'c\n' >> "dbg/jmp$N.ini"
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy hatari --machine st --memsize 1 \
  --tos /home/matt/projects/MJJ/bin/hatari/TOS/tos162fr.img --disk-a NITROWAV.ST \
  --protect-floppy on --borders on --fast-boot on --fast-forward on --frameskips 0 \
  --confirm-quit off --alert-level fatal --parse dbg/dump.ini --run-vbls "$((LAST + 20))" \
  > "$OUT.log" 2>&1 || true
grep -c savebin "$OUT.log" || true
