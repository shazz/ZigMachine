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
const depackers = @import("depackers");
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
extern fn m68k_get_reg(context: ?*anyopaque, reg: c_uint) c_uint;

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
/// Where a call gave up, for diagnosis when a tune will not run.
pub var stuck_pc: u32 = 0;

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
        // Only the EVEN byte of a word reaches the chip (see psgWrite).
        psgWrite(addr, @truncate(value >> 8));
    }
}

export fn m68k_write_memory_32(address: c_uint, value: c_uint) void {
    m68k_write_memory_16(address, (value >> 16) & 0xFFFF);
    m68k_write_memory_16(address +% 2, value & 0xFFFF);
}

// $FF8800 selects a register, $FF8802 writes the selected one.
//
// The YM is wired to the UPPER half of the 68000's data bus, so it only ever
// sees the even byte of a transfer: $FF8801 and $FF8803 go nowhere. That is not
// a detail to gloss over — it is exactly what makes `move.l #$rr00vv00,$ffff8800`
// set a register in one instruction, which is how a great many replay routines
// (Crystallized among them) drive the chip. Treat the odd bytes as writes and
// every value is immediately clobbered by the pad byte behind it: periods go
// half-right, volumes land on zero, and the tune plays silence.
fn psgWrite(addr: u32, value: u8) void {
    if (addr == PSG_BASE) {
        psg_latch = value & 0x0F;
    } else if (addr == PSG_BASE + 2) {
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

// --- just enough TOS -------------------------------------------------------
// An SNDH is supposed to be self-contained, but tunes converted from tracker
// sources habitually ask GEMDOS for a buffer at init and check the answer. With
// no TOS underneath, a TRAP vectors through a table that holds the tune's own
// header bytes and the CPU disappears into the weeds — which is exactly what
// Crystallized did. So the traps are answered here instead: a bump heap in the
// RAM above the tune, and honest zeroes for everything else.
const TRAP_GEMDOS = 1;
const GEMDOS_SUPER = 0x20;
const GEMDOS_MALLOC = 0x48;
const GEMDOS_MFREE = 0x49;
/// Room left below the stack that the heap may not grow into.
const STACK_ROOM: u32 = 0x10000;

var heap_next: u32 = 0;
var heap_end: u32 = 0;
/// The last trap we did not know how to answer, as (trap << 16) | function.
pub var unhandled_trap: u32 = 0;

fn heapReset(image_len: u32) void {
    heap_next = (image_len + 0xF) & ~@as(u32, 0xF);
    heap_end = STACK_TOP - STACK_ROOM;
}

fn malloc(size: u32) u32 {
    if (heap_next >= heap_end) return 0;
    const free = heap_end - heap_next;
    if (size == 0xFFFFFFFF) return free; // Malloc(-1): "how much is there?"
    const want = (size + 0xF) & ~@as(u32, 0xF);
    if (want > free) return 0;
    const at = heap_next;
    heap_next += want;
    return at;
}

/// Musashi calls this before taking a TRAP exception; non-zero means we handled
/// it and the CPU should carry on after the instruction. The stack has not been
/// touched yet, so A7 still points at the call's arguments.
export fn zmSndhTrap(trap: c_int) c_int {
    const sp = m68k_get_reg(null, REG_SP);
    const func = readWord(sp);
    if (trap != TRAP_GEMDOS) {
        unhandled_trap = (@as(u32, @intCast(trap)) << 16) | func;
        m68k_set_reg(REG_D0, 0);
        return 1;
    }
    const result: u32 = switch (func) {
        GEMDOS_MALLOC => malloc(readLong(sp + 2)),
        GEMDOS_MFREE => 0, // E_OK; a replay routine allocates once and keeps it
        GEMDOS_SUPER => 0, // already supervisor, and staying that way
        else => blk: {
            unhandled_trap = (@as(u32, TRAP_GEMDOS) << 16) | func;
            break :blk 0;
        },
    };
    m68k_set_reg(REG_D0, result);
    return 1;
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
        const image_len = if (depackers.isPacked(ram()[0..len])) open(len) orelse return false else len;
        const image = ram()[0..image_len];
        self.info = sndh.parse(image) orelse return false;
        self.tune = self.info.default_tune;
        self.samples_per_frame = @intFromFloat(audio.SAMPLE_RATE / @as(f32, @floatFromInt(self.info.hz)));

        heapReset(image_len);

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
        stuck_pc = m68k_get_reg(null, REG_PC);
        return false;
    }
};

/// Most SNDH tunes in the wild are crunched. Depacking is done HERE, in the
/// 68000's own RAM, because that is where a real ST would do it: the packed
/// image is moved out of the way into the top half of RAM and depacked back
/// down over address 0, where the replay routine expects to live. Returns the
/// depacked length, or null if it will not fit or the stream is corrupt.
const SCRATCH: u32 = RAM_SIZE / 2;

fn open(len: u32) ?u32 {
    const out_len = depackers.depackedLen(ram()[0..len]) orelse return null;
    // The two halves must not overlap, and the packed copy must clear the stack.
    if (out_len == 0 or out_len > SCRATCH or SCRATCH + len > MAX_IMAGE) return null;
    @memcpy(ram()[SCRATCH..][0..len], ram()[0..len]);
    return depackers.depack(ram()[SCRATCH..][0..len], ram()[0..out_len]);
}

// Every channel off: volumes to zero and the mixer set to "no tone, no noise".
fn silence() void {
    audio.machineYmWrite(7, 0xFF);
    for ([_]u32{ 8, 9, 10 }) |reg| audio.machineYmWrite(reg, 0);
}

fn readWord(addr: u32) u16 {
    if (addr + 1 >= RAM_SIZE) return 0;
    return (@as(u16, ram()[addr]) << 8) | ram()[addr + 1];
}

fn readLong(addr: u32) u32 {
    return (@as(u32, readWord(addr)) << 16) | readWord(addr + 2);
}

fn writeWord(addr: u32, value: u16) void {
    ram()[addr] = @truncate(value >> 8);
    ram()[addr + 1] = @truncate(value);
}

fn writeLong(addr: u32, value: u32) void {
    writeWord(addr, @truncate(value >> 16));
    writeWord(addr + 2, @truncate(value));
}
