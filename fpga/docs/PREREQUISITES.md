# Prerequisites: what to install, on the build machine and for the board

Two lists: the packages a machine needs to **build** the board's Linux image (Buildroot), and
what the **board** needs for a device beyond the keyboards, pads, mice and the USB floppy
(today: a Wi-Fi dongle). Everything else (Zig, uv, wabt, Verilator, Vivado) is in
`fpga/README.md` and `docs/BUILDING.md`.

## 1. Building the board's Linux image

`fpga/glass/boot/build_planA.sh` runs Buildroot (2026.02.3) on a build host (default
`omarchy`, `BUILD_HOST=local` for this machine). Buildroot refuses to start when one of its
host tools is missing. The two that a desktop install often lacks are **`wget`** and **`bc`**
(the kernel build calls `bc` to generate `timeconst.h`): on 9 Nov 2026 both were missing on
omarchy and Buildroot stopped with "You must install 'wget' / 'bc' on your build machine".

| Distribution | Command |
|---|---|
| Arch / Omarchy | `sudo pacman -S --needed wget bc rsync cpio unzip file patch perl python base-devel` |
| Debian / Ubuntu | `sudo apt install wget bc rsync cpio unzip file patch perl python3 build-essential` |
| Fedora | `sudo dnf install wget bc rsync cpio unzip file patch perl python3 gcc gcc-c++ make` |

Buildroot downloads its sources the first time (about 1 h for the whole image); a
`BR_DL_SEED=<dir>` with an older `dl/` saves the downloads.

## 2. On the board: Wi-Fi

No driver needs installing on the board: the image carries it. A dongle on the USB hub is
joined to the network named on the SD card at boot.

### Supported dongles

| Dongle | USB id | Driver | Firmware in the image | Status |
|---|---|---|---|---|
| Broadcom BCM43143 (the official Raspberry Pi dongle) | `0a5c:bd1e` | `brcmfmac` (built in) | `brcm/brcmfmac43143.bin` (6.10.198.66) | works: joined a WPA2 network, DHCP, internet and DNS (9 Nov 2026) |

Another dongle needs its kernel driver `=y` in `fpga/glass/boot/buildroot/linux.fragment`
(the image has no loadable modules: `post-build.sh` drops the module tree), its firmware
package in `configs/zigmachine_z7lite_defconfig`, and, for a Broadcom chip, its firmware file
added to `WIFI_FW_KEEP` in `post-build.sh` (only the files listed there are kept). `lsusb`
on a PC, or `cat /sys/bus/usb/devices/*/idVendor` on the board, gives the USB id; the Linux
wireless wiki (wireless.docs.kernel.org) names the driver for an id.

### Setting the network

From the board itself: F12, Console > `Wi-Fi...`, Scan networks, pick one, type its password
(docs/FPGA_GLASS.md, "The Wi-Fi page"). Glass writes the file below for you, hashed key only,
once the join worked. Or by hand: put a file `KESTREL/wifi.conf` on the SD card's FAT partition, in wpa_supplicant's format:

```
network={
    ssid="YourNetwork"
    psk="your password"
}
```

- At boot, `/etc/init.d/S99wifi` copies it to `/tmp/wifi/wpa.conf`, starts `wpa_supplicant`
  on `wlan0` and asks for an address by DHCP in the background: a missing network never
  delays the boot. No file, or no dongle: nothing happens.
- The password is in clear text on the card. To keep it off the card, store the hashed form
  instead: `wpa_passphrase "YourNetwork"` (on any Linux, or on the board) prints a
  `network={...}` block whose `psk=` is the 64-hex key; paste that block and delete the
  `#psk="..."` comment line it also prints. Anyone with the card can still join that
  network with the hashed key, but cannot read your password.
- Several `network={...}` blocks are fine; add `priority=N` to prefer one.
- Windows editors' CRLF line ends are fine (the script removes them).
- The board then answers as `zigmachine.local` (avahi). `ssh root@zigmachine.local` works with
  a key on the card in `authorized_keys` (S99glass installs it).

### Checking it on the board (serial console)

```
iw dev wlan0 link          # the access point and signal
wpa_cli -i wlan0 status    # wpa_state=COMPLETED when joined
ip addr show wlan0         # the address DHCP gave
cat /tmp/wifi/wpa.log      # wpa_supplicant's log (it never prints the password)
```

## 3. On the board: Ethernet (not yet)

The RJ45 is not usable yet: the Linux side is configured (`eth0`, DHCP, dropbear, avahi),
but the bitstream does not wire the PS's Ethernet controller (GEM0, through EMIO) to the
RTL8201F PHY on the PL's pins (`docs/FPGA_GLASS.md`, "Remote shell over Ethernet"). A cable
gives a link light, because the PHY negotiates by itself, but no traffic.
