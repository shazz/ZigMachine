# install.sh: copy /tmp/up/<path> to the card for each path in /tmp/up/up_list.txt, old files to KESTREL/rollback/syncterm1
# SyncTERM spike (branch port/syncterm-spike): the SyncTERM DATA disk CARTS/tools/demo-syncterm.zmd, its program's fat
# disk KESTREL/progs/demo-syncterm/BOOT.WSM.zmd (the cart's LEAN board image for system table 1.17, as on the card
# since the notepad install: system.rv32 and KOS's desktop are NOT replaced), and the by-hash image (GEM run from a
# real floppy). Needs the desk mode (HW 1.17.0 bitstream). The syncterm shelf.txt line (/tmp/up/shelf_line.txt) is
# APPENDED to the card's CARTS/shelf.txt if that file has no syncterm line (the old shelf.txt goes to the rollback
# dir first). Glass is unchanged: it is restarted so the OSD rescans.
# Rollback: copy KESTREL/rollback/syncterm1/* back, delete CARTS/tools/demo-syncterm.zmd, KESTREL/progs/demo-syncterm/
# and the syncterm by-hash file (they had no old copy), and restart glass.
S=/mnt/sd; R=$S/KESTREL/rollback/syncterm1
mount -o remount,rw $S || exit 1
mkdir -p $R
while read f; do
  if [ -f $S/$f ]; then mkdir -p $R/$(dirname $f); cp $S/$f $R/$f; fi
  mkdir -p $S/$(dirname $f); cp /tmp/up/$f $S/$f
done < /tmp/up/up_list.txt
if [ -f $S/CARTS/shelf.txt ]; then
  mkdir -p $R/CARTS; cp $S/CARTS/shelf.txt $R/CARTS/shelf.txt
  grep -q 'demo-syncterm.zmd' $S/CARTS/shelf.txt || { [ -n "$(tail -c1 $S/CARTS/shelf.txt)" ] && echo >> $S/CARTS/shelf.txt; cat /tmp/up/shelf_line.txt >> $S/CARTS/shelf.txt; }
fi
sync
cd $S; while read f; do md5sum $f; done < /tmp/up/up_list.txt; echo "rollback files: $(find $R -type f | wc -l)"
grep 'demo-syncterm.zmd' CARTS/shelf.txt || echo "shelf.txt: no syncterm line (the OSD shows the disk's own title)"
md5sum -c /tmp/up/MD5SUMS_up && echo "md5 check: all OK" || echo "md5 check: MISMATCH (see above)"
cd /; mount -o remount,ro $S
killall glass; sleep 8; echo "glass pid $(pidof glass)"
