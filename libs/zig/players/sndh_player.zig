// --------------------------------------------------------------------------
// SNDH player — an OPEN ZigOS player that runs the tune's own 68000 code on a
// Musashi core (libs/c/musashi) and traps its PSG writes to the SEALED YM2149.
//
// This is the honest shape of Atari ST music. An SNDH is not a register dump,
// it is a replay routine: 68000 code that pokes $FFFF8800/02 a few hundred
// times a second. So the machine emulates the CPU and the MACHINE'S OWN chip
// makes the sound — the same division as the real hardware, and the reason we
// do not use sc68's software YM (or its Emscripten build, which would put the
// whole job back in the page).
//
// Memory map given to the 68000 (24-bit, as a 68000 has):
//
//   $000000..$0FFFFF   1 MiB of RAM — the shared song RAM, so the image the
//                      worklet staged IS the 68000's memory, with no copy. The
//                      tune sits at $0, where its three branch instructions
//                      stand in for the reset vectors it never takes.
//   $0FFE00            supervisor stack, growing down
//   $0FFF00            a planted NOP used as the return address (see call())
//   $FF8800..$FF8803   the PSG: select at 8800, write-data at 8801/8802/8803
//   everything else    reads 0, ignores writes. Timers and the MFP are NOT
//                      emulated: `play` is called by us, at the rate the SNDH
//                      header asks for, which is what those timers exist to do.
// --------------------------------------------------------------------------
const std = @import("std");
const audio = @import("audio_hw");
const sndh = @import("sndh.zig");

// --- Musashi ---------------------------------------------------------------
const CPU_TYPE_68000: c_uint = 1; // M68K_CPU_TYPE_68000
const REG_D0: c_uint = 0; // indices into m68k_register_t
const REG_PC: c_uint = 16;
const REG_SP: c_uint = 18;

extern fn m68k_init() void;
extern fn m68k_set_cpu_type(cpu_type: c_uint) void;
extern fn m68k_pulse_reset() void;
extern fn m68k_execute(num_cycles: c_int) c_int;
extern fn m68k_end_timeslice() void;
extern fn m68k_set_reg(reg: c_uint, value: c_uint) void;

// --- the 68000's world -----------------------------------------------------
const RAM_SIZE: u32 = @intCast(audio.SONG_CAP);
const STACK_TOP: u32 = RAM_SIZE - 0x200;
const RETURN_PC: u32 = RAM_SIZE - 0x100;
const NOP: u16 = 0x4E71;
/// The most RAM a tune may occupy, leaving the stack somewhere to live.
const MAX_IMAGE: u32 = RAM_SIZE - 0x10000;

const PSG_BASE: u32 = 0xFF8800;
const ADDRESS_MASK: u32 = 0x00FFFFFF; // a 68000 has 24 address lines

/// A replay call that has not returned within this many cycles has lost its
/// way. An 8 MHz 68000 has ~160k cycles per 50 Hz frame; no replay routine
/// wants a whole second of them.
const RUNAWAY_CYCLES: u32 = 8_000_000;

fn ram() [*]u8 {
    return @ptrFromInt(audio.SONG_BASE);
}

var psg_latch: u8 = 0;
var returned: bool = false;

// --- the bus: Musashi calls these ------------------------------------------
export fn m68k_read_memory_8(address: c_uint) c_uint {
    const addr = @as(u32, @intCast(address)) & ADDRESS_MASK;
    if (addr < RAM_SIZE) return ram()[addr];
    return 0;
}

export fn m68k_read_memory_16(address: c_uint) c_uint {
    const addr = @as(u32, @intCast(address)) & ADDRESS_MASK;
    if (addr + 1 < RAM_SIZE) return (@as(c_uint, ram()[addr]) << 8) | ram()[addr + 1];
    return 0;
}

export fn m68k_read_memory_32(address: c_uint) c_uint {
    const addr = @as(u32, @intCast(address)) & ADDRESS_MASK;
    if (addr + 3 < RAM_SIZE) {
        return (@as(c_uint, ram()[addr]) << 24) | (@as(c_uint, ram()[addr + 1]) << 16) |
            (@as(c_uint, ram()[addr + 2]) << 8) | ram()[addr + 3];
    }
    return 0;
}

export fn m68k_write_memory_8(address: c_uint, value: c_uint) void {
    const addr = @as(u32, @intCast(address)) & ADDRESS_MASK;
    const byte: u8 = @truncate(value);
    if (addr < RAM_SIZE) {
        ram()[addr] = byte;
    } else {
        psgWrite(addr, byte);
    }
}

export fn m68k_write_memory_16(address: c_uint, value: c_uint) void {
    const addr = @as(u32, @intCast(address)) & ADDRESS_MASK;
    if (addr + 1 < RAM_SIZE) {
        ram()[addr] = @truncate(value >> 8);
        ram()[addr + 1] = @truncate(value);
    } else {
        // A word write to $FF8800 is the idiomatic ST "select and set": the high
        // byte lands on the select port and the low byte on its data mirror.
        psgWrite(addr, @truncate(value >> 8));
        psgWrite(addr + 1, @truncate(value));
    }
}

export fn m68k_write_memory_32(address: c_uint, value: c_uint) void {
    m68k_write_memory_16(address, (value >> 16) & 0xFFFF);
    m68k_write_memory_16(address +% 2, value & 0xFFFF);
}

// $FF8800 selects a register; $FF8801/02/03 all write the selected one (the ST
// mirrors the write-data port across the odd/even pair).
fn psgWrite(addr: u32, value: u8) void {
    if (addr < PSG_BASE or addr > PSG_BASE + 3) return;
    if (addr == PSG_BASE) {
        psg_latch = value & 0x0F;
    } else {
        audio.machineYmWrite(psg_latch, value);
    }
}

/// Musashi calls this before every instruction (see config/m68kconf.h). It is
/// how a replay call ends: the CPU reaching the planted return address.
export fn zmSndhInstructionHook(pc: c_uint) void {
    if (pc == RETURN_PC) {
        returned = true;
        m68k_end_timeslice();
    }
}

// --- the player ------------------------------------------------------------
pub const SndhPlayer = struct {
    active: bool = false,
    info: sndh.Info = .{},
    tune: u8 = 1,
    samples_per_frame: u32 = 882,
    frame_acc: u32 = 0,

    /// The image is ALREADY in song RAM (the worklet staged it there), which is
    /// the 68000's RAM, so loading is just: is this really an SNDH, and will it
    /// leave room for a stack?
    pub fn load(self: *SndhPlayer, len: u32) bool {
        self.* = .{};
        if (len == 0 or len > MAX_IMAGE) return false;
        const image = ram()[0..len];
        self.info = sndh.parse(image) orelse return false;
        self.tune = self.info.default_tune;
        self.samples_per_frame = @intFromFloat(audio.SAMPLE_RATE / @as(f32, @floatFromInt(self.info.hz)));

        // The return stub the replay routine will RTS to.
        writeWord(RETURN_PC, NOP);

        m68k_init();
        m68k_set_cpu_type(CPU_TYPE_68000);
        m68k_pulse_reset();
        return true;
    }

    pub fn start(self: *SndhPlayer, tune: u8) void {
        if (self.info.hz == 0) return;
        self.tune = if (tune >= 1 and tune <= self.info.subtunes) tune else self.info.default_tune;
        silence();
        self.active = self.call(sndh.INIT, self.tune);
        self.frame_acc = 0;
    }

    pub fn stop(self: *SndhPlayer) void {
        if (self.active) _ = self.call(sndh.EXIT, 0);
        self.active = false;
        silence(); // an exit routine that forgets to must not leave a note hanging
    }

    /// One replay call, then the chip is rendered for the samples it covers —
    /// the same shape as YmPlayer, so the two are interchangeable to the worklet.
    pub fn renderStereo(self: *SndhPlayer, frames: usize) void {
        const n = @min(frames, audio.MAX_FRAMES);
        audio.machineClear(@intCast(n));
        var off: usize = 0;
        while (off < n) {
            if (self.frame_acc == 0) {
                if (!self.call(sndh.PLAY, 0)) {
                    self.active = false;
                    silence();
                    break;
                }
                self.frame_acc = self.samples_per_frame;
            }
            const block = @min(@as(u32, @intCast(n - off)), self.frame_acc);
            audio.machineRenderYm(@intCast(off), block);
            self.frame_acc -= block;
            off += block;
        }
        audio.machineClamp(@intCast(n));
    }

    // Call one of the tune's three entry points as a subroutine and run the CPU
    // until it returns. Returns false if it never did — a tune that has run off
    // into garbage is stopped rather than left to eat the audio thread on every
    // block from now on.
    fn call(self: *SndhPlayer, entry: u32, d0: u32) bool {
        _ = self;
        writeLong(STACK_TOP - 4, RETURN_PC);
        m68k_set_reg(REG_SP, STACK_TOP - 4);
        m68k_set_reg(REG_D0, d0);
        m68k_set_reg(REG_PC, entry);

        returned = false;
        var spent: u32 = 0;
        while (spent < RUNAWAY_CYCLES) {
            const used = m68k_execute(20_000);
            spent += if (used > 0) @intCast(used) else 1;
            if (returned) return true;
        }
        return false;
    }
};

// Every channel off: volumes to zero and the mixer set to "no tone, no noise".
fn silence() void {
    audio.machineYmWrite(7, 0xFF);
    for ([_]u32{ 8, 9, 10 }) |reg| audio.machineYmWrite(reg, 0);
}

fn writeWord(addr: u32, value: u16) void {
    ram()[addr] = @truncate(value >> 8);
    ram()[addr + 1] = @truncate(value);
}

fn writeLong(addr: u32, value: u32) void {
    writeWord(addr, @truncate(value >> 16));
    writeWord(addr + 2, @truncate(value));
}
