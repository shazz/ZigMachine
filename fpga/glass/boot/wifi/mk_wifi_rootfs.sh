#!/bin/sh
# mk_wifi_rootfs.sh BASE.cpio.uboot OUT.cpio.uboot: append a second newc cpio holding the Wi-Fi driver,
# firmware, tools and S99wifi (the overlay's, which insmods /usr/lib/kwifi when wlan0 is missing)
# to a rootfs image. The kernel unpacks concatenated archives in order; the base stays byte for byte.
# Until the Buildroot image builds Wi-Fi in, this is what lets the board rejoin by itself at boot.
set -e
here=$(cd "$(dirname "$0")" && pwd); repo=$(cd "$here/../../../.." && pwd); w=$(mktemp -d)
S=${ZM_WIFI_BIN:-$repo/prototypes/board_wifi/wifi}; r=$w/root  # the built driver/tools (local, not in git)
mkdir -p $r/usr/lib/kwifi $r/lib/firmware/brcm $r/usr/sbin $r/etc/init.d
cp $S/cfg80211.ko $S/brcmutil.ko $S/brcmfmac.ko $S/brcmfmac-wcc.ko $r/usr/lib/kwifi/
cp $here/kwifi_modprobe $r/usr/lib/kwifi/modprobe
cp $S/brcmfmac43143.bin $r/lib/firmware/brcm/; cp $S/regulatory.db $S/regulatory.db.p7s $r/lib/firmware/
cp $S/wpa_supplicant $S/iw $S/wpa_cli $r/usr/sbin/; cp $S/libnl-3.so.200 $S/libnl-genl-3.so.200 $r/usr/lib/
cp $repo/fpga/glass/boot/buildroot/overlay/etc/init.d/S99wifi $r/etc/init.d/
find $r -type d -exec chmod 755 {} +   # the kernel chmods existing dirs to the archive's modes
chmod 755 $r/usr/lib/kwifi/modprobe $r/etc/init.d/S99wifi $r/usr/sbin/*; chmod 644 $r/usr/lib/kwifi/*.ko
(cd $r && find . -mindepth 1 | sed 's|^\./||' | sort | cpio -o -H newc -R 0:0 --quiet) > $w/wifi.cpio
dd if="$1" of=$w/base.cpio bs=64 skip=1 status=none
cat $w/base.cpio $w/wifi.cpio > $w/all.cpio
"$repo/fpga/build/buildroot/host/bin/mkimage" -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n '' -d $w/all.cpio "$2" >/dev/null
rm -rf $w; md5sum "$2"
