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

// --- the request block, at window end - CART_REQ_FROM_TOP (CPU 0x41FF_FD00) --------
// Four words, CART_REQ_MAGIC, the request, the name's bytes, ~(magic ^ request ^
// bytes), then the name: the FAT name the request matched (host/zmd_dir.h), at most
// CART_REQ_NAME_MAX bytes. Written by the firmware BEFORE it sets CART_REQUEST; the
// glass takes it only when the check holds.
pub const CART_REQ_FROM_TOP: u32 = 0x300;
pub const CART_REQ_MAGIC: u32 = 0x5152_4D5A; // "ZMRQ"
pub const CART_REQ_HEAD_WORDS: u32 = 4;
pub const CART_REQ_NAME_MAX: u32 = 48;

// --- the disk descriptor's other magic -----------------------------------------
// map.zig's DISK_MAGIC: the cart was booted for this disk (GEM over a data disk
// hands it the listing). DISK_MAGIC_PROGRAM: the cart is a program GEM launched off
// it (the browser's diskDirSet is already true then: no listing).
pub const DISK_MAGIC_PROGRAM: u32 = 0x5044_4D5A; // "ZMDP"

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
pub const SI_CYCLES: u32 = 5; // the last render: its CPU cycles ...
pub const SI_SAMPLES: u32 = 6; // ... for this many 44.1 kHz samples
pub const SI_PEAK_CYCLES: u32 = 7; // the dearest render per sample since the song started
pub const SI_PEAK_SAMPLES: u32 = 8;
pub const SI_NAME: u32 = 9; // the song's name, NUL-padded, to the block's end
pub const SND_NAME_MAX: u32 = (SND_INFO_WORDS - SI_NAME) * 4 - 1; // 59 bytes and a NUL
pub const SIF_STARTED: u32 = 1 << 0; // its player started (else: no such file, or refused)
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
pub const PLAYER_UNKNOWN: u32 = 0xFF; // an extension no player takes
// SI_HEAD's native (PLAYER_SNDH only): demo-audio's audioSndhNative() (players/digi.zig Status).
pub const NATIVE_MUSASHI: u32 = 0;
pub const NATIVE_BEAT_DIS: u32 = 1;
pub const NATIVE_NEAR_SEQ: u32 = 2; // the digi handler with an unknown sequencer: on Musashi
pub const NATIVE_NEAR_TABLES: u32 = 3; // the driver's tables out of range: on Musashi
pub const NATIVE_OFF: u32 = 4; // native replays switched off: on Musashi

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
pub const VS_PAINTED: u32 = 9; // command write to PAINTED: the pass's row load, fetch, paint
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
