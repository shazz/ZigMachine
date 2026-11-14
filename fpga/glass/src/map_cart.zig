// What ZWINDOW (the glass) and ZIGGY's firmware say to each other beyond map.zig's
// registers, for a program launched off a data disk (docs/FPGA_GLASS.md, "Programs
// off a data disk"). All of it is software over what the PL already has: a value of
// REG_CART_STATE the firmware writes, words in the cart window's top 4 KiB, and a
// second descriptor magic. No register, no RTL. Exported like map.zig
// (tools/glass_export.zig) to gen/glass_cart.{py,h}.

// --- REG_CART_STATE: the cart asks for a cart swap ----------------------------
// Bits 31:8 = the request, as pollCartRequest() returned it (docs/sealed-loader.js
// swapCart): REQ_RUN_PROGRAM runs the FAT file named in the request block as the next
// cart, the disk staying in; REQ_BACK_TO_OS brings GEM back over the same disk.
pub const CART_REQUEST: u32 = 4;
pub const REQ_RUN_PROGRAM: u32 = 3;
pub const REQ_BACK_TO_OS: u32 = 4;
// A bootable cart's swaps (swapCart's req 1 and -1): REQ_LOAD_CART boots the shelf disk
// demo-<tag>.zmd, the tag in the request block (the Union Demo's street doors);
// REQ_BACK (the cart's -1, which 31:8 cannot hold) goes back to the cart that loaded it.
pub const REQ_LOAD_CART: u32 = 1;
pub const REQ_BACK: u32 = 0xFF;

// --- the request block, at window end - CART_REQ_FROM_TOP (CPU 0x41FF_FD00) --------
// Four words, CART_REQ_MAGIC, the request, the name's bytes, ~(magic ^ request ^
// bytes), then the name: the FAT name the request matched (host/zmd_dir.h), at most
// CART_REQ_NAME_MAX bytes. Written by the firmware BEFORE it sets CART_REQUEST; the
// glass takes it only when the check holds.
pub const CART_REQ_FROM_TOP: u32 = 0x300;
pub const CART_REQ_MAGIC: u32 = 0x5152_4D5A; // "ZMRQ"
pub const CART_REQ_HEAD_WORDS: u32 = 4;
pub const CART_REQ_NAME_MAX: u32 = 48;

// --- the desktop's mode word, at window end - DESK_REZ_FROM_TOP (CPU 0x41FF_FCFC) --------
// Getrez across a program load (rom/rom_deskmode.zig): a program GEM launched, and the desktop
// it quits back to, are each a new image whose ROM starts fresh. The firmware writes DESK_REZ_TAG
// | the mode (0 low, 1 medium, 2 desk; rom deskReturnMode) BEFORE the request block; for
// REQ_RUN_PROGRAM and REQ_BACK_TO_OS the glass reads it before the load and writes it again after
// the window is verified (loader.zig Options.desk_rez). Every other load leaves it zero; the
// firmware zeroes it once read, and ignores it on a reset (KOS's boot words: cycles/bkos.c).
// Between the C: sector block and the request block.
pub const DESK_REZ_FROM_TOP: u32 = 0x304;
pub const DESK_REZ_TAG: u32 = 0x5200_0000; // "R"
pub const DESK_REZ_TAG_MASK: u32 = 0xFF00_0000;

// --- the boot sector's skip word, at window end - BOOTSEC_SKIP_FROM_TOP (CPU 0x41FF_FC20) ----
// A disk's executable boot sector (fpga/cycles/bbootsec.c) runs when the disk goes in, as in
// the browser; not when a program quits back to the OS over the same disk (swapCart req 4),
// which on the board is a load of the same fat disk. That load writes BOOTSEC_SKIP here, after
// the window is verified; every other load leaves it zero (the window is rewritten whole), so
// a stale one never survives. Between the descriptor and the request block, both unused here.
pub const BOOTSEC_SKIP_FROM_TOP: u32 = 0x3E0;
pub const BOOTSEC_SKIP: u32 = 0x5342_4D5A; // "ZMBS"

// --- KOS's boot words, at window end - KOS_BOOT_FROM_TOP (CPU 0x41FF_FC28) -------------
// KOS, the KESTREL Operating System (docs/ZIGTOS_BOOT.md): a reset the glass makes (power-on,
// R, W, the shelf's Enter) writes KOS_BOOT_MAGIC, then flags: KOS_WARM for W, and in bits
// 23:8 the POST's frames (0: none, glass.cfg post=0 or a key held). The firmware
// (cycles/bkos.c) reads them once at boot. A load that is no reset (a program run off the
// disk, back to the desktop, a door's cart) writes neither, so no POST runs, as the browser's
// swaps show none. Between the boot sector's skip word and the request block.
pub const KOS_BOOT_FROM_TOP: u32 = 0x3D8;
pub const KOS_BOOT_MAGIC: u32 = 0x424B_4D5A; // "ZMKB"
pub const KOS_BOOT_WORDS: u32 = 2;
pub const KOS_WARM: u32 = 1 << 0;
pub const KOS_POST_SHIFT: u32 = 8;
pub const KOS_POST_MASK: u32 = 0xFFFF;
pub const KOS_POST_FRAMES: u32 = 180; // rom/kos/kos.zig POST_FRAMES: 3 s
// Drive A's media change while a cart runs (app_drive.zig, docs/ZIGTOS_BOOT.md 4.1): the glass
// zeroes the disk descriptor, writes the new disk after the running image (or none: eject), the
// descriptor again, then bumps this word: KOS_MEDIA_TAG | a count in bits 23:0. The firmware
// (cycles/bdiskapp.c) reads it once a frame past its D-cache line; a new value means the drive
// changed: it reads the descriptor again, tells the cart (insertDisk) and KOS (kosMediaChange).
// A load zeroes it, so the firmware starts from the value it finds at boot.
pub const KOS_MEDIA_FROM_TOP: u32 = 0x3D0;
pub const KOS_MEDIA_TAG: u32 = 0x4D00_0000;
pub const KOS_MEDIA_COUNT: u32 = 0x00FF_FFFF;
// KOS's C:, sector by sector (docs/KOS_FAT.md F5, env.kosDriveRead), at window end -
// KOS_DRIVE_FROM_TOP (CPU 0x41FF_FCA0, between the media word and the request block). The
// firmware (cycles/bkosreq.h) writes unit, first sector, count (1..KOS_DRIVE_MAX_SECTORS), the
// window offset the sectors go to (the cart's dst), a sequence number, the check ~(magic ^ seq ^
// unit ^ sector ^ count ^ offset), the magic last. glass (src/kos_drive.zig, a thread at ~2 kHz)
// reads the sectors off the SD card's partition into the window there, writes KD_DONE (the count
// read, 0 refused) and KD_ACK = the sequence, last. The firmware gives up after KOS_DRIVE_TIMEOUT_MS.
pub const KOS_DRIVE_FROM_TOP: u32 = 0x360;
pub const KOS_DRIVE_MAGIC: u32 = 0x444B_4D5A; // "ZMKD"
pub const KOS_DRIVE_WORDS: u32 = 9;
pub const KD_MAGIC: u32 = 0;
pub const KD_SEQ: u32 = 1;
pub const KD_UNIT: u32 = 2;
pub const KD_SECTOR: u32 = 3;
pub const KD_COUNT: u32 = 4;
pub const KD_OFFSET: u32 = 5;
pub const KD_CHECK: u32 = 6;
pub const KD_DONE: u32 = 7;
pub const KD_ACK: u32 = 8;
pub const KOS_DRIVE_UNIT_C: u32 = 2;
pub const KOS_DRIVE_MAX_SECTORS: u32 = 64;
pub const KOS_DRIVE_TIMEOUT_MS: u32 = 500;
// KOS's C:, its writes (docs/KOS_GEMDOS.md §7, env.kosFileOp, rom/kos/kfs_abi.zig), at window end -
// KOS_FILE_FROM_TOP (CPU 0x41FF_FC40, 32-byte aligned, between the C: generation word and the sector
// block). A cart never writes sectors: glass writes whole files under the card's /HD through Linux's FAT
// (src/kos_file.zig, polled by the C: thread). The firmware (cycles/bkosfile.c) copies the cart's
// request in: the operation, its flags, slot, attributes and offset, the data's and the paths'
// window offsets and lengths, a sequence, the check ~(magic ^ every word from KF_SEQ to
// KF_PATH2_LEN), the magic last. glass copies the paths and data OUT of the window before it checks
// them, then answers KF_DONE (a TOS code, as a u32) and KF_ACK = the sequence, last; after a write it
// bumps the generation word (KOS_CGEN_FROM_TOP), which the firmware reads for the `gen` operation.
// A write remounts the card read-write, fsyncs and remounts it read-only: KOS_FILE_TIMEOUT_MS.
pub const KOS_FILE_FROM_TOP: u32 = 0x3C0;
pub const KOS_FILE_MAGIC: u32 = 0x464B_4D5A; // "ZMKF"
pub const KOS_FILE_WORDS: u32 = 17;
pub const KF_MAGIC: u32 = 0;
pub const KF_SEQ: u32 = 1;
pub const KF_OP: u32 = 2;
pub const KF_FLAGS: u32 = 3;
pub const KF_SLOT: u32 = 4;
pub const KF_ATTR: u32 = 5;
pub const KF_OFFSET: u32 = 6;
pub const KF_LEN: u32 = 7;
pub const KF_DATA: u32 = 8;
pub const KF_PATH: u32 = 9;
pub const KF_PATH_LEN: u32 = 10;
pub const KF_PATH2: u32 = 11;
pub const KF_PATH2_LEN: u32 = 12;
pub const KF_CHECK: u32 = 13;
pub const KF_DONE: u32 = 14;
pub const KF_ACK: u32 = 15;
// glass took the request (KF_TAKEN = its sequence, written as soon as the block is whole and checked,
// before the write itself): the firmware gives up after KOS_FILE_TAKE_MS without it (EWRPRO: no glass,
// an older one, or one built for another KOS_FILE_FROM_TOP: the first board run lost a save that way)
// instead of waiting KOS_FILE_TIMEOUT_MS. glass writes the window only in answer to a request: a word it
// wrote on every poll made each cart load's read-back fail (loader.zig DdrMismatch).
pub const KF_TAKEN: u32 = 16;
pub const KOS_FILE_TAKE_MS: u32 = 250;
pub const KOS_FILE_DATA_MAX: u32 = 32768; // rom/kos/kfs_abi.zig DATA_MAX
pub const KOS_FILE_PATH_MAX: u32 = 127; // kfs_abi.zig PATH_MAX
pub const KOS_FILE_TIMEOUT_MS: u32 = 10000;
pub const KOS_CGEN_FROM_TOP: u32 = 0x3CC; // CPU 0x41FF_FC34: the C: generation: glass bumps it after each write it made

// --- ZIGNIC's request block, at window end - NET_FROM_TOP (CPU 0x41FF_FB80) ------------------
// env.netOp on the board (docs/GEM_NET.md N2, machine/sdk/net_abi.zig): the firmware (cycles/bnet.c) copies
// the cart's Req into NB_OP..NB_HOST_LEN (buf and host as WINDOW OFFSETS, checked against the cart's memory),
// then NB_CHECK, then NB_MAGIC last, and spins; glass (src/net_card.zig, polled by the C: thread) copies the
// block, checks it, runs the op on Linux's sockets (never blocking), writes NB_OUT.. (state, events, err,
// peer_ip, peer_port, local_port) and NB_DONE (the op's i32), then NB_ACK = the sequence last. Data moves
// in place in the cart's memory (glass reads buf for send, writes it for recv). Below the disk descriptor
// (map.zig DISK_DESC_FROM_TOP 0x400), in the top 4 KiB the link keeps free.
pub const NET_FROM_TOP: u32 = 0x480;
pub const NET_MAGIC: u32 = 0x4E4E_4D5A; // "ZMNN"
pub const NET_WORDS: u32 = 20;
pub const NB_MAGIC: u32 = 0;
pub const NB_SEQ: u32 = 1;
pub const NB_OP: u32 = 2; // op, sock, a0, a1, buf, len, host, host_len: the Req's first 8 words
pub const NB_HOST_LEN: u32 = 9;
pub const NB_CHECK: u32 = 10; // ~(NET_MAGIC ^ seq ^ every word NB_OP..NB_HOST_LEN)
pub const NB_TAKEN: u32 = 11;
pub const NB_DONE: u32 = 12; // the op's answer (an i32)
pub const NB_ACK: u32 = 13;
pub const NB_OUT: u32 = 14; // state, events, err, peer_ip, peer_port, local_port: the Req's words 8..13
pub const NB_OUT_WORDS: u32 = 6;
pub const NET_TIMEOUT_MS: u32 = 100; // the firmware's wait: glass's ops never block, so it answers in < 1 ms

// --- the video mode word, at window end - VMODE_FROM_TOP (CPU 0x41FF_FC38) -----
// The pointer's geometry depends on the cart's screen mode (docs/GEM_DESK_MODE.md §4): the
// desk mode (RESOLUTION = RES_DESK, HW 1.17.0) is 640x480 at 1:1, the plane modes 640x200 on
// the 800x280 raster with rows twice as tall. ZIGGY's firmware (cycles/bdesk.c) writes
// VMODE_TAG, with VMODE_DESK while the cart is in the desk, at each frame it changes; glass
// reads it at each mouse report (mouse.zig). A load zeroes it: no tag (an older firmware, or no
// frame yet) is the plane modes. Between the C: generation word and the C: file block.
pub const VMODE_FROM_TOP: u32 = 0x3C8;
pub const VMODE_TAG: u32 = 0x5600_0000; // "V"
pub const VMODE_TAG_MASK: u32 = 0xFF00_0000;
pub const VMODE_DESK: u32 = 1 << 0;

// --- the pointer's box: two words, at window end - VBOX_X_FROM_TOP / VBOX_Y_FROM_TOP -----
// Where the cart's picture is, so the pointer stops there in the plane modes (Matt, 9 Nov): GEM's
// one 640x200 plane is the visible window (the arrow never goes into the borders); pt2-clone's
// 320x255 and klystrack's 320x240, centred in 400x280 planes, reach their top and bottom rows and
// no further (their own cursor is drawn only over the picture: past it, it vanished). ZIGGY's
// firmware (cycles/bptrbox.h, bdesk.c) writes the rectangle the cart published with
// env.hostPointerBox (the SDL layer: kestrel_sdl2/src/kestrel_ptrbox.c), else the union of its
// enabled planes' rectangles (each the whole raster or the visible window: vwhole.h), whenever
// it changes; glass reads both words at each mouse report (mouse.zig planeBox). Raster
// coordinates, medium-res x, ends exclusive, exact: VBOX_X = VBOX_X_TAG | x0 | x1 << VBOX_HI_SHIFT
// (CPU 0x41FF_FC3C, between VMODE and the C: file block), VBOX_Y = VBOX_Y_TAG | y0 | y1 <<
// VBOX_HI_SHIFT (CPU 0x41FF_FC24, between the boot sector's skip word and KOS's boot words). The
// firmware stores y then x; a report between the two sees a box that is still on the raster, and
// the next one sees the whole of it. Either word untagged (an older firmware, no frame yet: a load
// zeroes them) is the whole raster. The desk mode ignores them (its 640x480 picture).
pub const VBOX_X_FROM_TOP: u32 = 0x3C4;
pub const VBOX_Y_FROM_TOP: u32 = 0x3DC;
pub const VBOX_X_TAG: u32 = 0x5800_0000; // "X"
pub const VBOX_Y_TAG: u32 = 0x5900_0000; // "Y"
pub const VBOX_TAG_MASK: u32 = 0xFF00_0000;
pub const VBOX_FIELD_MASK: u32 = 0x3FF;
pub const VBOX_HI_SHIFT: u32 = 12;

// --- the disk descriptor's other magic -----------------------------------------
// map.zig's DISK_MAGIC: the cart was booted for this disk (GEM over a data disk
// hands it the listing). DISK_MAGIC_PROGRAM: the cart is a program GEM launched off
// it (the browser's diskDirSet is already true then: no listing).
pub const DISK_MAGIC_PROGRAM: u32 = 0x5044_4D5A; // "ZMDP"
// DISK_MAGIC_FLOPPY: as DISK_MAGIC, the disk being the real floppy (glass's D, KOS): the desktop
// labels drive A FLOPPY, not SD IMAGE (docs/KOS_FAT.md F4; insertDisk's bit 8).
pub const DISK_MAGIC_FLOPPY: u32 = 0x4644_4D5A; // "ZMDF"

// --- the system image and lean carts (decisions.md 2026-10-15) ------------------
// A lean cart image is linked at window offset CART_IMG_AT and starts with its header:
// CART_HDR_MAGIC, the system-table version it needs at CART_HDR_VERSION_AT (major << 16 |
// minor), and the CPU address its .bss ends at CART_HDR_BSS_END_AT (the disk goes after
// it). The system image (firmware + machine + ROM + BARD) sits at 0 and must end by
// CART_IMG_AT. On the SD card the system is zigmachine/system.rv32: a SYS_HEAD_WORDS-word
// header (SYS_MAGIC, version, image bytes, ~(magic ^ version ^ bytes)) before the image,
// ZX0-packed. fpga/cycles/sys_abi.txt is the table's layout and version.
pub const CART_IMG_AT: u32 = 0x0030_0000;
pub const CART_HDR_MAGIC: u32 = 0x4143_4D5A; // "ZMCA"
pub const CART_HDR_VERSION_AT: u32 = 4;
pub const CART_HDR_BSS_END_AT: u32 = 16;
pub const SYS_MAGIC: u32 = 0x5953_4D5A; // "ZMSY"
pub const SYS_HEAD_WORDS: u32 = 4;
// REG_CART_STATE TRAPPED codes (map.zig TRAP_WARM_LOST's family): the cart needs another
// table version than the system has; nothing that is a cart sits at CART_IMG_AT.
pub const TRAP_CART_ABI: u32 = 0xFF_FF02;
pub const TRAP_NO_CART: u32 = 0xFF_FF03;

// --- the music: who plays it (the debug page, docs/FPGA_GLASS.md "Who plays the music") --
// The debug mailbox (cycles/bmailbox.h) is the cart window's last MB_BYTES; its first words
// are MB_MAGIC and the mailbox version. From MB_VERSION_SND_INFO, ZIGGY's firmware zeroes
// the whole page at boot, and its last SND_INFO_WORDS words (window end - SND_INFO_FROM_TOP,
// CPU 0x41FF_FFA0) are the music block, written by whichever CPU runs the players (BARD,
// or ZIGGY in a ZM_AUDIO=1 image; cycles/bsndinfo.h): no magic there = no music in this
// firmware. The writer bumps SI_SEQ to odd, writes, bumps it to even: a reader that sees
// the same even SI_SEQ before and after its copy has a whole block.
pub const MB_BYTES: u32 = 0x100;
pub const MB_MAGIC: u32 = 0x424D_4D5A; // "ZMMB"
pub const MB_VERSION_SND_INFO: u32 = 2;
pub const SND_INFO_FROM_TOP: u32 = 0x60;
pub const SND_INFO_WORDS: u32 = 24;
pub const SND_INFO_MAGIC: u32 = 0x4953_4D5A; // "ZMSI"
pub const SND_INFO_VERSION: u32 = 1; // SI_HEAD bits 7:0: a reader decodes only a version it knows
pub const SI_MAGIC: u32 = 0;
pub const SI_SEQ: u32 = 1;
pub const SI_HEAD: u32 = 2; // version | route << 8 | player << 16 | native << 24
pub const SI_TUNE: u32 = 3; // the request's tune: an SNDH's subtune, a MOD's start BPM
pub const SI_FLAGS: u32 = 4; // SIF_*
pub const SI_CYCLES: u32 = 5; // the load now: the CPU cycles of the last whole window of renders (~1 s, bsndinfo.h) ...
pub const SI_SAMPLES: u32 = 6; // ... for this many 44.1 kHz samples
pub const SI_PEAK_CYCLES: u32 = 7; // the dearest single render per sample since the song started
pub const SI_PEAK_SAMPLES: u32 = 8;
pub const SI_NAME: u32 = 9; // the song's name, NUL-padded, to the block's end
pub const SND_NAME_MAX: u32 = (SND_INFO_WORDS - SI_NAME) * 4 - 1; // 59 bytes and a NUL
pub const SIF_STARTED: u32 = 1 << 0; // its player started (else: no such file, or refused)
// SI_FLAGS bits 9:8: the SNDH mode in force after the song's last zg.requestSndhMode (1 the
// tune's 68000 code on Musashi, 2 native, 3 native with the samples on PCM). 0 = none asked
// since the load, or a firmware before this field: the reader derives 1 or 2 from SI_HEAD's
// native, which is what a load leaves (sndh_native.zig recognise). Only a switch is written,
// and a new song clears it with the rest of SI_FLAGS.
pub const SIF_MODE_SHIFT: u32 = 8;
pub const SIF_MODE_MASK: u32 = 3;
// The render's clock: both CPUs run at the sys clock, so a 60 Hz frame's 735 samples have
// 1.67 Mc of it: load = cycles * SND_RATE_HZ / (samples * SND_CLOCK_HZ).
pub const SND_CLOCK_HZ: u32 = 100_000_000;
pub const SND_RATE_HZ: u32 = 44_100;
// SI_HEAD's route: who runs the players.
pub const ROUTE_NONE: u32 = 0; // never written: no music in this firmware
pub const ROUTE_ZIGGY: u32 = 1; // the cart CPU (a ZM_AUDIO=1 image)
pub const ROUTE_BARD: u32 = 2; // the sound CPU
pub const ROUTE_BARD_DOWN: u32 = 3; // built for BARD, which never answered: no music
// SI_HEAD's player: what host/audio.c's audio_play picks by the name's extension.
pub const PLAYER_NONE: u32 = 0; // nothing asked yet, or "none"
pub const PLAYER_SNDH: u32 = 1; // the tune's 68000 code: Musashi, or a native driver (SI_HEAD's native)
pub const PLAYER_SAP: u32 = 2; // 6502 + POKEY
pub const PLAYER_MOD: u32 = 3;
pub const PLAYER_XM: u32 = 4; // FT2
pub const PLAYER_YM: u32 = 5; // a .ymraw register dump
pub const PLAYER_PCM: u32 = 6; // .raw
pub const PLAYER_HIP: u32 = 7; // a Hippel Amiga module's own 68000 replay on Musashi + Paula
pub const PLAYER_PAULA: u32 = 8; // no player: the cart drives the Paula channels itself (env.hostPaulaClaim, HW 1.14)
pub const PLAYER_KT: u32 = 9; // a klystrack song: cyd on the Paula channels (libs/zig/players/kt.zig)
pub const PLAYER_MP3: u32 = 10; // a cart's MP3 stream decoded on BARD (env.hostMp3Ctl/Feed, libs/zig/players/mp3.zig)
pub const PLAYER_SID: u32 = 11; // a Commodore 64 PSID on cRSID: BARD native, machine-audio.wasm on the page (libs/zig/players/sid.zig)
pub const PLAYER_AY: u32 = 12; // a cart's AY / YM chips live on the BARD queue (ChipNomad: zg.bard AY writes, libs/c/ayumi)
pub const PLAYER_UNKNOWN: u32 = 0xFF; // an extension no player takes
// SI_HEAD's native (PLAYER_SNDH only): demo-audio's audioSndhNative() (players/digi.zig Status).
pub const NATIVE_MUSASHI: u32 = 0;
pub const NATIVE_BEAT_DIS: u32 = 1;
pub const NATIVE_NEAR_SEQ: u32 = 2; // the digi handler with an unknown sequencer: on Musashi
pub const NATIVE_NEAR_TABLES: u32 = 3; // the driver's tables out of range: on Musashi
pub const NATIVE_OFF: u32 = 4; // native replays switched off: on Musashi
// 5 .. NATIVE_LAST: more native drivers (players/digi.zig Status: Monty ... B.I.G. native).
pub const NATIVE_LAST: u32 = 16;

// --- the video probe: where FRESCO's time goes (perf/fresco-probe) ------------------------
// Mailbox words VSTAT_AT .. VSTAT_AT + VSTAT_WORDS - 1, unused before: mb_init zeroes them, so a
// firmware without the probe leaves no magic there. ZIGGY's sequencer (cycles/vseq.c built with
// ZM_VSTAT) times each phase of every frame; cycles/bvstat.h sums VSTAT_FRAMES frames (fewer once
// they pass VSTAT_MAX_CYCLES) and publishes their PER-FRAME MEANS, bracketed by VS_SEQ odd then
// even as the music block is. Cycles are the sys clock's (SND_CLOCK_HZ) except VS_COMP, which
// counts the compositor's own clock (125 MHz on the board) while a pass runs.
pub const VSTAT_AT: u32 = 16;
pub const VSTAT_WORDS: u32 = 16;
pub const VSTAT_MAGIC: u32 = 0x5356_4D5A; // "ZMVS"
pub const VSTAT_FRAMES: u32 = 16;
pub const VSTAT_MAX_CYCLES: u32 = 100_000_000; // a window of slow frames closes after ~1 s
pub const VS_MAGIC: u32 = 0;
pub const VS_SEQ: u32 = 1;
pub const VS_N: u32 = 2; // frames in the window the means are over
pub const VS_FLAGS: u32 = 3; // VSF_*, and bits 15:8 the cycles one counter read costs
pub const VS_FRAME: u32 = 4; // the first mean: a whole frame, end to end
pub const VS_CART: u32 = 5; // cart.frame() (+ the disk app's step)
pub const VS_SEQC: u32 = 6; // the sequencer: clear, planner, every pass, PRESENT
pub const VS_READY: u32 = 7; // waiting for READY: the last pass's mix and store
pub const VS_DRAIN: u32 = 8; // waiting for DRAINED: the handler's stores reaching FRESCO
pub const VS_PAINTED: u32 = 9; // command write to PAINTED (row load, fetch, paint), less VS_PLAN's
pub const VS_HBL: u32 = 10; // inside the HBL handlers
pub const VS_PLAN: u32 = 11; // the dirty-line planner: its frame compare and per-line decisions
pub const VS_PASSES: u32 = 12; // BG, PLANE and MIX passes issued
pub const VS_COMP: u32 = 13; // compositor clocks a pass was running (COMP_BUSY)
pub const VS_DMA: u32 = 14; // sys cycles the video DMA held a request (DMA_BUSY, scanout included)
pub const VS_SWAP: u32 = 15; // waiting for the shown picture to swap (the VBL)
pub const VSF_UNDERRUN: u32 = 1 << 0; // the scanout's sticky `underrun` (since the PL's reset)
pub const VSF_OVERFLOW: u32 = 1 << 1; // the plane fetch's sticky `overflow`
pub const VSF_UNDERRUN_AT_BOOT: u32 = 1 << 2; // `underrun` was already set when this cart booted
// The probe's boot calibration (cycles/vcal.c), at window end - VCAL_FROM_TOP (CPU 0x41FF_FD80,
// between the request block and bdiag's control words): before the cart's first frame, VCAL_REPS
// MIX passes of each kind on raster line 0, timed. Each kind is two words: the mean sys cycles
// from the command's write to READY (what the sequencer sees), and the mean compositor clocks
// it ran (COMP_BUSY). The kinds differ by one row read or write, so the row costs follow:
//   MIX1  load PFB, mix, store picture              (R + mix + W)
//   MIX2  load PFB + picture, mix, store picture    (2R + mix + W)
//   FILL1 paint the CLEAR colour, mix, store both   (fill + mix + 2W)
//   FILL2 paint, load picture, mix, store both      (fill + R + mix + 2W)
// Written at each probe firmware's boot; a firmware without the probe leaves the last one's.
pub const VCAL_FROM_TOP: u32 = 0x280;
pub const VCAL_WORDS: u32 = 10;
pub const VCAL_MAGIC: u32 = 0x4356_4D5A; // "ZMVC"
pub const VCAL_REPS: u32 = 8;
pub const VC_MAGIC: u32 = 0;
pub const VC_REPS: u32 = 1;
pub const VC_MIX1: u32 = 2; // {span, comp}
pub const VC_MIX2: u32 = 4;
pub const VC_FILL1: u32 = 6;
pub const VC_FILL2: u32 = 8;
// The system's A/B switches (glass run --fw-opt, src/afi.zig): the word at window end -
// FW_OPT_FROM_TOP (CPU 0x41FF_FE08, cycles/bdiag.h's control word +8), written by every load after
// the window is verified, read once by the firmware at boot. FW_OPT_TAG | bits; untagged = all off.
pub const FW_OPT_FROM_TOP: u32 = 0x1F8;
pub const FW_OPT_TAG: u32 = 0xC0F0_0000;
pub const FW_OPT_W64: u32 = 1 << 1; // the video DMA's 8-byte write beats (hp_cfg W64): HP1's AFI 64-bit
pub const FW_OPT_PLANE_MAJOR: u32 = 1 << 4; // no line-major groups (cycles/bplanes.h)
pub const FW_OPT_KEEP_PFB: u32 = 1 << 5; // the top layer stores its PFB rows too
pub const FW_OPT_MASK: u32 = FW_OPT_W64 | FW_OPT_PLANE_MAJOR | FW_OPT_KEEP_PFB;
