# KESTREL on a blank Z7-Lite: from the tarball to a running cart

This release carries a whole SD card in `card/`: the boot files, the KESTREL system, the shelf of
carts and an empty `HD/`. A MicroPhase Z7-Lite **7010** with nothing on it boots it as it is. You
need no Vivado, no JTAG cable and no SoC sources. (The 7020 board is not supported: its PS7 setup
and its FPGA differ.)

## 1. The SD card

1. Take a card of 1 GB or more. Make **one partition**, MBR (DOS) partition table, type FAT32,
   and format it FAT32. The Zynq BootROM reads `BOOT.BIN` from the first partition only.
   - Linux: `sudo fdisk /dev/sdX` (o, n, p, 1, defaults, t, c, w), then `sudo mkfs.vfat -F 32 /dev/sdX1`
   - macOS: `diskutil eraseDisk FAT32 KESTREL MBRFormat /dev/diskN`
   - Windows: the SD Association's "SD Card Formatter", or Disk Management (FAT32)
2. Copy the **contents** of `card/` onto the card's root, not the folder itself. The root must
   then hold `BOOT.BIN`, `boot.scr`, `zigmachine.bit`, `zImage`, ... and the folders `KESTREL/`,
   `CARTS/`, `HD/`.
3. Check the copy before you eject (`card.md5` lists every file):

   ```sh
   cd /media/$USER/KESTREL && md5sum -c --quiet /path/to/kestrel-sdk-<version>/card.md5
   ```

   No output means every file is right. Eject the card cleanly (`sync`, then eject).

## 2. The board

- **Jumper `J1` on SD** (boot from the card, not JTAG).
- **HDMI1** to a monitor or a TV (the picture is 800x600 at 60 Hz, sound on HDMI).
- A **USB keyboard** on the board's USB host port; a USB pad (Xbox-style, or most HID pads) works
  too, through a hub if you want both.
- Optional: the **UART, `J3`** (a CH340 USB-serial) to a PC, **921600 baud, 8N1**. It is the boot
  console: `picocom -b 921600 /dev/ttyUSB0`, `screen /dev/ttyUSB0 921600`, or PuTTY on Windows
  (macOS: `/dev/tty.usbserial-*`, with the CH340 driver on older systems).
- Insert the card, then power the board.

## 3. What to expect

On the serial console, within about ten seconds:

1. zeST's U-Boot (`U-Boot 2025.01 ...`); it runs `boot.scr` at once (no countdown);
2. `boot.scr` loads `zigmachine.bit` into the FPGA, then the Linux kernel, its device tree and
   the initramfs;
3. Linux boots (`Linux version 6.19.14 ...`), and `S99glass` mounts the card read-only on
   `/mnt/sd` and starts **glass**, the console's ARM side. It says which layout it found:

   ```
   card /mnt/sd: kestrel layout, system /mnt/sd/KESTREL, carts /mnt/sd/CARTS
   ```

4. A `zigmachine login:` prompt (user `root`, no password) is there if you want a shell; you
   never need it to use the console.

On the screen: the KOS POST (the ZigMachine's power-on screen, `KOS 1.0`), then the **GEM
desktop**: drive A is empty on a new card (FLOPPY says `Drive A: is empty`) and `C:` is the card's
`HD/` folder, empty for now. Files you put in `HD/` from a PC show in GEM.

## 4. The first cart

- **F12** opens the menu (the OSD). Its folders are the shelf's categories: `demos`, `games`,
  `tools`, `tutorials`, `tests`. Pick a disk with the arrows and Enter: it goes in
  drive A and the console resets onto it.
- Try `tutorials` then `TUTORIAL` first: a small screen with rasters, a scroller and music. Then
  `demos`: the ST demo ports.
- **F12** again (or **Esc**) closes the menu over the running cart. **F11** shows the frame rate.
- The menu's console page sets the volume; glass keeps it, and the disk in drive A, in
  `KESTREL/glass.cfg` on the card for the next power-on.

## 5. Your own cart

The SDK's three commands, from `template/` (or a copy of it next to `zigmachine/`):

| Command | What you get |
|---|---|
| `make` | your cart in the browser emulator, on a local web server (`make cart` only builds it) |
| `make floppy` | your cart on a disk image, `zig-out/demo-<name>.zmd` |
| `make board` | the board image and `zig-out/sd/`: this card plus your cart in `CARTS/demos/` |

`zigmachine/tools/sdk_doctor.sh --board` lists the tools to install first. Then copy the contents
of `zig-out/sd/` onto the card (it is the whole card again, with your cart and its line in
`CARTS/shelf.txt`), and your cart is in the menu. The guide: `zigmachine/docs/SDK.md`.

## If it does not boot

- **Nothing on the UART at all:** the jumper is on JTAG, or `BOOT.BIN` is not at the root of the
  first FAT partition (check the partition table: MBR, one FAT32 partition).
- **U-Boot prints but stops** at a `Zynq>` prompt: `boot.scr` is missing or damaged; check the
  card with `card.md5`.
- **`zigmachine: no zigmachine.bit on the card`**, or a black screen after Linux: copy the card
  again and check it with `card.md5`.
- **Linux runs but the menu says a file is missing:** the card is incomplete or from another
  release; `KESTREL/system.rv32` and the carts in `CARTS/` must come from the same release.
