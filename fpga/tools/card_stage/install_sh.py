"""install.sh: the one template every staged card ships (run on the board: `sh /tmp/up/install.sh`).

Copies /tmp/up/<path> over the card for each path of up_list.txt, keeps the FIRST old copy of each
file in KESTREL/rollback/<card name>/, then checks every md5. It refuses a card whose KESTREL/BOARD
names another board. ZM_SD / ZM_UP point it at a directory for the tests (no remount then)."""

from __future__ import annotations

TEMPLATE = r"""# install.sh: card @NAME@ for @BOARD@ (staged by fpga/tools/card.py).
# Copies $U/<path> to the card for each path in $U/up_list.txt, old files to KESTREL/rollback/@NAME@, then checks every md5.
# Rollback: copy KESTREL/rollback/@NAME@/<path> back over <path> for each, delete those in its NEW.txt.
S=${ZM_SD:-/mnt/sd}; U=${ZM_UP:-/tmp/up}; R=$S/KESTREL/rollback/@NAME@; BOARD=@BOARD@
if [ -f $S/KESTREL/BOARD ]; then
  have=$(cat $S/KESTREL/BOARD)
  [ "$have" = "$BOARD" ] || { echo "REFUSED: this card is a $have card, not $BOARD"; exit 1; }
elif [ "$BOARD" != kestrel ]; then
  echo "REFUSED: the card has no KESTREL/BOARD (an old KESTREL card), not a $BOARD card"; exit 1
fi
if [ $# -gt 0 ]; then printf '%s\n' "$@" > $U/this_list.txt; else cp $U/up_list.txt $U/this_list.txt; fi
[ -n "$ZM_SD" ] || mount -o remount,rw $S || exit 1
mkdir -p $R; touch $R/NEW.txt
while read f; do
  if [ -f $S/$f ]; then
    # keep the FIRST old copy: a second run must not overwrite the rollback with the new file
    [ -f $R/$f ] || { mkdir -p $R/$(dirname $f); cp $S/$f $R/$f; }
  else
    grep -qx "$f" $R/NEW.txt || echo $f >> $R/NEW.txt
  fi
  mkdir -p $S/$(dirname $f); cp $U/$f $S/$f.new && mv $S/$f.new $S/$f  # rename: a running KESTREL/glass is never written in place
done < $U/this_list.txt
sync
cd $S; while read f; do md5sum $f; done < $U/this_list.txt; echo "rollback files: $(find $R -type f | wc -l)"
echo "new files (no old copy):"; cat $R/NEW.txt
grep -F -f $U/this_list.txt $U/MD5SUMS_up | md5sum -c - && echo "md5 check: all OK" || echo "md5 check: MISMATCH (see above)"
cd /; sync; [ -n "$ZM_SD" ] || mount -o remount,ro $S
"""


def render(name: str, board: str) -> str:
    return TEMPLATE.replace("@NAME@", name).replace("@BOARD@", board)
