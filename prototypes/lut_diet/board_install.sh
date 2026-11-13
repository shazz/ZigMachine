#!/bin/bash
# board_install.sh BIT: over the board's Wi-Fi shell (root@192.168.0.16), keep the card's zigmachine.bit
# in KESTREL/rollback/lutdiet_prev/ (md5 checked), write BIT as /mnt/sd/zigmachine.bit (md5 checked
# after the copy and again after sync), then reboot: U-Boot loads the new PL image. The Wi-Fi is RAM-only,
# so after the reboot the board is reached over the serial console (fpga/tools, --tty).
# Rollback (serial): mount -o remount,rw /mnt/sd; cp /mnt/sd/KESTREL/rollback/lutdiet_prev/zigmachine.bit
# /mnt/sd/zigmachine.bit; sync; reboot
set -euo pipefail
bit=$1
B="ssh -o BatchMode=yes root@192.168.0.16"
sum=$(md5sum "$bit" | cut -d' ' -f1)
echo "new bitstream md5 $sum"
$B 'mount -o remount,rw /mnt/sd && mkdir -p /mnt/sd/KESTREL/rollback/lutdiet_prev && cp /mnt/sd/zigmachine.bit /mnt/sd/KESTREL/rollback/lutdiet_prev/zigmachine.bit && sync && md5sum /mnt/sd/zigmachine.bit /mnt/sd/KESTREL/rollback/lutdiet_prev/zigmachine.bit'
cat "$bit" | $B 'cat > /mnt/sd/zigmachine.bit.new && sync && md5sum /mnt/sd/zigmachine.bit.new'
got=$($B 'md5sum /mnt/sd/zigmachine.bit.new' | cut -d" " -f1)
[ "$got" = "$sum" ] || { echo "md5 MISMATCH after upload ($got), nothing installed"; $B 'rm /mnt/sd/zigmachine.bit.new'; exit 1; }
$B 'mv /mnt/sd/zigmachine.bit.new /mnt/sd/zigmachine.bit && sync && md5sum /mnt/sd/zigmachine.bit && mount -o remount,ro /mnt/sd; echo lutdiet-installed'
echo "rebooting the board"
$B 'touch /tmp/glass.stop; killall glass; sleep 1; reboot' || true
