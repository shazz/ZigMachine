// --------------------------------------------------------------------------
// The Atari 8-bit around a SAP player's 6502 (sap_player.zig): 64 KiB of RAM,
// the POKEY's registers, and the few other registers players touch. In song
// RAM, above the staged file (a SAP and an SNDH never play at once).
//
//   $D200-$D2FF  POKEY, mirrored every 16 bytes. Writes are queued with the
//                CPU's cycle, for the player to play at their sample; RANDOM
//                ($D20A) reads a 17-bit poly stepped by the cycles; other reads $FF
//   $D40A WSYNC  a write stalls the CPU to the end of its 114-cycle line
//   $D40B VCOUNT the line / 2, counted from the frame's cycles
//   $D014 PAL    1 on PAL, $F on NTSC (GTIA's PAL register: players check it)
//   $D000-$D7FF  everything else: reads 0, writes COUNTED (`unknown`) and dropped
//   the rest     RAM (the OS ROM is not there: a SAP brings its own code)
//
// Not modelled: ANTIC's DMA cycle-stealing (the stamps are early by its share,
// inaudible at 44.1 kHz), IRQs (no TYPE D), the second POKEY (no STEREO).
// --------------------------------------------------------------------------
const audio = @import("audio_hw");

pub const RAM_AT: usize = 0x80000; // the Atari's RAM, this far into song RAM
pub const QUEUE_AT: usize = RAM_AT + 0x10000; // the write queue, after it: in song RAM, not a zeroed static
pub const LINE: u64 = 114; // CPU cycles a scanline
pub const MAX_WRITES: usize = 512; // POKEY writes queued a frame

pub const Write = struct { cycle: u64, reg: u4, val: u8 };

pub var cycles: *const u64 = &zero; // the CPU's cycle counter (sap_player sets it)
pub var stall: u64 = 0; // cycles WSYNC added (sap_player folds them into the CPU's)
pub var frame_start: u64 = 0; // the cycle the current frame began at
pub var frame_lines: u64 = 312;
pub var pal: bool = true;
pub var unknown: u32 = 0; // hardware writes that went nowhere
pub fn queue() *[MAX_WRITES]Write {
    return @ptrFromInt(audio.SONG_BASE + QUEUE_AT);
}
pub var queued: usize = 0;
pub var overflow: u32 = 0; // POKEY writes lost to a full queue
var poly: u32 = 0x1FFFF;
var poly_at: u64 = 0;
const zero: u64 = 0;

pub fn ram() *[65536]u8 {
    return @ptrFromInt(audio.SONG_BASE + RAM_AT);
}

fn now() u64 {
    return cycles.* + stall;
}

/// RANDOM: the 17-bit poly's top byte, stepped once a cycle up to now.
fn random() u8 {
    var n = @min(now() - poly_at, 131071);
    poly_at = now();
    while (n > 0) : (n -= 1) poly = (poly >> 1) | ((~(poly ^ (poly >> 5)) & 1) << 16);
    return @truncate(poly >> 9);
}

pub fn read(a: u16) u8 {
    if (a < 0xD000 or a >= 0xD800) return ram()[a];
    if (a & 0xFF00 == 0xD200) return if (a & 0x0F == 0x0A) random() else 0xFF;
    if (a == 0xD40B) return @truncate(((now() - frame_start) / LINE % frame_lines) / 2);
    if (a == 0xD014) return if (pal) 1 else 0x0F;
    return 0;
}

pub fn write(a: u16, v: u8) void {
    if (a < 0xD000 or a >= 0xD800) {
        ram()[a] = v;
    } else if (a & 0xFF00 == 0xD200) {
        if (queued == MAX_WRITES) {
            overflow +%= 1;
            return;
        }
        queue()[queued] = .{ .cycle = now(), .reg = @truncate(a), .val = v };
        queued += 1;
    } else if (a == 0xD40A) {
        stall += LINE - (now() - frame_start) % LINE;
    } else unknown +%= 1;
}

pub fn reset(is_pal: bool, lines: u64) void {
    stall = 0;
    frame_start = 0;
    pal = is_pal;
    frame_lines = lines;
    unknown = 0;
    queued = 0;
    overflow = 0;
    poly = 0x1FFFF;
    poly_at = 0;
}
