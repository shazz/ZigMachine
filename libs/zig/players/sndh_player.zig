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
//   $000000..$0FFFFF   1 MiB of RAM — the shared song RAM. The worklet stages
//                      the file at $0; load() moves (or depacks) it up to
//                      IMAGE_BASE and zeroes the rest, as a fresh ST would be.
//   $000000..$0003FF   the exception vector table, EMPTY until the tune fills
//                      it: a SID tune installs its MFP handlers at $110/$120/
//                      $134 itself. The image used to sit HERE, and those
//                      writes overwrote its own code (Alloy Run: silence).
//   $010002            the image: init / exit / play at +0 / +4 / +8, then the
//                      tune's code and data. The heap starts right after it.
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
/// Where the image lives in 68000 RAM: AtariAudio's SNDH_UPLOAD_ADDR
/// (SndhRenderer.h), which it chose because some tunes cannot play below it and
/// some crash when loaded exactly on the 64 KiB boundary. Above the vector table
/// and the system variables, so a tune that installs its own vectors does not
/// write over itself.
const IMAGE_BASE: u32 = 0x10002;
/// The top of the region a tune may occupy, leaving the stack somewhere to live.
const IMAGE_TOP: u32 = RAM_SIZE - 0x10000;
/// The most bytes a tune may occupy.
const MAX_IMAGE: u32 = IMAGE_TOP - IMAGE_BASE;

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
/// What we last wrote to each YM register, for the chip's read-back port.
var ym_shadow: [16]u8 = [_]u8{0} ** 16;
var returned: bool = false;
/// Where a call gave up, for diagnosis when a tune will not run.
pub var stuck_pc: u32 = 0;

// --- the bus: Musashi calls these ------------------------------------------
export fn m68k_read_memory_8(address: c_uint) c_uint {
    const addr = @as(u32, @intCast(address)) & ADDRESS_MASK;
    if (addr < RAM_SIZE) return ram()[addr];
    // $FF8800 reads back the SELECTED register — a replay that preserves the
    // mixer's port bits does a read-modify-write through it.
    if (addr == PSG_BASE) return ym_shadow[psg_latch];
    if (addr >= MFP_BASE and addr < MFP_BASE + MFP_SIZE) return mfpRead(addr);
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
        hwWrite(addr, byte);
    }
}

export fn m68k_write_memory_16(address: c_uint, value: c_uint) void {
    const addr = @as(u32, @intCast(address)) & ADDRESS_MASK;
    if (addr + 1 < RAM_SIZE) {
        ram()[addr] = @truncate(value >> 8);
        ram()[addr + 1] = @truncate(value);
    } else {
        // Only the EVEN byte of a word reaches the PSG (see psgWrite); the MFP
        // is byte-wide on odd addresses, so a word write there lands on both.
        hwWrite(addr, @truncate(value >> 8));
        if (addr >= MFP_BASE and addr < MFP_BASE + MFP_SIZE) hwWrite(addr + 1, @truncate(value));
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
        ym_shadow[psg_latch] = value;
        audio.machineYmWrite(psg_latch, value);
    }
}

/// Everything above RAM: the PSG, the MFP, and silence for the rest.
fn hwWrite(addr: u32, value: u8) void {
    if (addr >= PSG_BASE and addr <= PSG_BASE + 3) return psgWrite(addr, value);
    if (addr >= MFP_BASE and addr < MFP_BASE + MFP_SIZE) return mfpWrite(addr, value);
}

/// Musashi calls this before every instruction (see config/m68kconf.h). It is
/// how a replay call ends: the CPU reaching the planted return address.
export fn zmSndhInstructionHook(pc: c_uint) void {
    if (pc == RETURN_PC) {
        returned = true;
        m68k_end_timeslice();
    }
}

// --- the MFP 68901's timers ------------------------------------------------
// A replay routine is interrupt code. The tune's header names the timer that
// should call `play` (TC50 here) and the player provides that itself — but a
// maxYMiser-style tune ALSO programs a second timer, usually Timer A at a few
// kHz, whose handler feeds the volume registers to play digidrums. Without it
// that voice never moves and the drums are simply absent.
//
// So the MFP's timer registers are shadowed here and any timer OTHER than the
// one driving `play` gets its handler called at the rate it asks for.
const MFP_BASE: u32 = 0xFFFA00;
const MFP_SIZE: u32 = 0x40;
const MFP_CLOCK: f32 = 2457600.0;
/// Timer control prescalers, indexed by the low 3 bits of the control register.
const PRESCALE = [8]u16{ 0, 4, 10, 16, 50, 64, 100, 200 };
/// Registers, as offsets from $FFFA00 (the MFP lives on odd addresses).
const VR = 0x17; // vector register: its top nibble is the vector base
const TACR = 0x19;
const TBCR = 0x1B;
const TCDCR = 0x1D; // timer C in bits 4-6, timer D in bits 0-2
const TADR = 0x1F;
const TBDR = 0x21;
const TCDR = 0x23;
const TDDR = 0x25;
/// A timer's interrupt channel number, which picks its vector.
const CHANNEL = [4]u8{ 13, 8, 5, 4 }; // A, B, C, D
/// Refuse to emulate a timer faster than this: a tune that programs a silly
/// rate must not be able to hang the audio thread.
const MAX_TIMER_HZ: f32 = 40000.0;
/// A timer_acc that will never come due.
const NEVER: u32 = 0xFFFFFFFF;
/// Timer accumulators are 16.16 fixed point IN SAMPLES. They have to be: a
/// digidrum timer at 15360 Hz wants an interrupt every 2.871 samples, and
/// rounding that to 2 would play the drum 43% sharp — which does not sound like
/// a fast drum, it sounds like noise.
const ONE: u32 = 1 << 16;

/// TOS leaves the vector register at $40, and tunes count on it: they install
/// their handlers at the standard addresses ($120 for Timer B, $134 for Timer A)
/// without ever writing VR themselves. Start the MFP the way a booted ST hands
/// it over, or the vectors are computed from a base of 0 and point into the
/// tune's own header.
const VR_TOS_DEFAULT: u8 = 0x40;

var mfp: [MFP_SIZE]u8 = [_]u8{0} ** MFP_SIZE;

fn mfpReset() void {
    mfp = [_]u8{0} ** MFP_SIZE;
    mfp[VR] = VR_TOS_DEFAULT;
}

fn mfpWrite(addr: u32, value: u8) void {
    mfp[addr - MFP_BASE] = value;
}

fn mfpRead(addr: u32) u8 {
    return mfp[addr - MFP_BASE];
}

/// How often timer `t` (0=A..3=D) wants its interrupt, or 0 when it is stopped.
fn timerHz(t: usize) f32 {
    const ctrl: u8 = switch (t) {
        0 => mfp[TACR] & 0x0F,
        1 => mfp[TBCR] & 0x0F,
        2 => (mfp[TCDCR] >> 4) & 0x07,
        else => mfp[TCDCR] & 0x07,
    };
    // Bit 3 is event-count mode, which counts an external signal, not the clock.
    if (ctrl == 0 or ctrl > 7) return 0;
    const data: u16 = switch (t) {
        0 => mfp[TADR],
        1 => mfp[TBDR],
        2 => mfp[TCDR],
        else => mfp[TDDR],
    };
    const count: f32 = if (data == 0) 256 else @floatFromInt(data);
    const hz = MFP_CLOCK / (@as(f32, @floatFromInt(PRESCALE[ctrl])) * count);
    return if (hz > MAX_TIMER_HZ) 0 else hz;
}

/// Where timer `t`'s handler lives, or 0 if the tune installed none.
fn timerVector(t: usize) u32 {
    const base: u32 = mfp[VR] & 0xF0;
    const addr = (base | CHANNEL[t]) * 4;
    const handler = readLong(addr);
    return if (handler == 0 or handler >= RAM_SIZE) 0 else handler;
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

// XBIOS Xbtimer(timer, control, data, vector): how a digidrum tune starts its
// MFP timer through TOS instead of poking $FFFA19 itself. Mad Max's
// "Auf Weidersehen Monty - digidrums" does; unanswered, its drum timer never
// ran. Program the shadowed MFP exactly as a direct write would, so rearm()
// picks the timer up after init/play like any other, and install the handler
// at the timer's vector.
const TRAP_XBIOS = 14;
const XBIOS_XBTIMER = 0x1F;

fn xbtimer(sp: u32) void {
    const t = readWord(sp + 2);
    if (t > 3) return;
    const ctrl: u8 = @truncate(readWord(sp + 4));
    const data: u8 = @truncate(readWord(sp + 6));
    const vector = readLong(sp + 8);
    switch (t) {
        0 => {
            mfp[TACR] = ctrl & 0x0F;
            mfp[TADR] = data;
        },
        1 => {
            mfp[TBCR] = ctrl & 0x0F;
            mfp[TBDR] = data;
        },
        2 => {
            mfp[TCDCR] = (mfp[TCDCR] & 0x0F) | ((ctrl & 0x07) << 4);
            mfp[TCDR] = data;
        },
        else => {
            mfp[TCDCR] = (mfp[TCDCR] & 0xF0) | (ctrl & 0x07);
            mfp[TDDR] = data;
        },
    }
    const slot = ((@as(u32, mfp[VR]) & 0xF0) | CHANNEL[t]) * 4;
    if (vector != 0 and vector < RAM_SIZE) writeLong(slot, vector);
}

var heap_next: u32 = 0;
var heap_end: u32 = 0;
/// What rate each MFP timer is programmed at, for diagnosis (0 = stopped).
pub fn timerRate(t: usize) u32 {
    return if (t < 4) @intFromFloat(timerHz(t)) else 0;
}

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
    if (trap == TRAP_XBIOS and func == XBIOS_XBTIMER) {
        xbtimer(sp);
        m68k_set_reg(REG_D0, 0);
        return 1;
    }
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

/// Call a timer's handler as an INTERRUPT. It ends in RTE, not RTS, so what
/// goes on the stack is a 68000 group-2 exception frame — status register then
/// return PC — and RTE pops both.
const REG_SR: c_uint = 17;
const SR_SUPERVISOR_MASKED: u32 = 0x2700;

fn callInterrupt(handler: u32) bool {
    const sp = STACK_TOP - 6;
    writeWord(sp, @truncate(SR_SUPERVISOR_MASKED));
    writeLong(sp + 2, RETURN_PC);
    m68k_set_reg(REG_SP, sp);
    m68k_set_reg(REG_SR, SR_SUPERVISOR_MASKED);
    m68k_set_reg(REG_PC, handler);
    return runUntilReturn();
}

fn runUntilReturn() bool {
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

// --- the player ------------------------------------------------------------
pub const SndhPlayer = struct {
    active: bool = false,
    info: sndh.Info = .{},
    tune: u8 = 1,
    samples_per_frame: u32 = 882,
    frame_acc: u32 = 0,
    /// Replay frames played since `start`. A screen that syncs its animation to
    /// the music needs a clock, and this is the honest one: the tune's own.
    frames_played: u32 = 0,
    /// Per MFP timer (A..D): samples between interrupts and samples still to
    /// go, both 16.16 fixed point. NEVER = the timer is not running.
    timer_period: [4]u32 = [_]u32{0} ** 4,
    timer_acc: [4]u32 = [_]u32{NEVER} ** 4,

    /// The file is ALREADY in song RAM (the worklet staged it at $0), which is
    /// the 68000's RAM, so loading is: is this really an SNDH, will it leave room
    /// for a stack, and move it up to IMAGE_BASE out of the vector table.
    pub fn load(self: *SndhPlayer, len: u32) bool {
        self.* = .{};
        if (len == 0 or len > MAX_IMAGE) return false;
        const packed_file = depackers.isPacked(ram()[0..len]);
        // Check it is an SNDH before anything is moved: a refused file must
        // leave song RAM as the worklet staged it.
        if (!packed_file and sndh.parse(ram()[0..len]) == null) return false;
        const image_len = if (packed_file) open(len) orelse return false else place(len);
        self.info = sndh.parse(ram()[IMAGE_BASE..][0..image_len]) orelse return false;
        self.tune = self.info.default_tune;
        self.samples_per_frame = @intFromFloat(audio.SAMPLE_RATE / @as(f32, @floatFromInt(self.info.hz)));

        heapReset(IMAGE_BASE + image_len);

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
        mfpReset(); // a fresh MFP, as TOS would hand it over
        self.active = self.call(sndh.INIT, self.tune);
        self.frame_acc = 0;
        self.frames_played = 0;
        self.rearm(); // init is where a tune programs its digidrum timer
    }

    /// How far into the tune we are, in milliseconds.
    pub fn positionMs(self: *const SndhPlayer) u32 {
        if (self.info.hz == 0) return 0;
        return self.frames_played *% 1000 / self.info.hz;
    }

    pub fn stop(self: *SndhPlayer) void {
        if (self.active) _ = self.call(sndh.EXIT, 0);
        self.active = false;
        silence(); // an exit routine that forgets to must not leave a note hanging
    }

    /// Render a block, running the tune's interrupts at the right moments
    /// inside it: `play` at the header's rate, plus any OTHER MFP timer the
    /// tune has programmed (a digidrum timer runs at a few kHz, so it fires
    /// many times per replay frame). Same shape as YmPlayer, so the two remain
    /// interchangeable to the worklet.
    pub fn renderStereo(self: *SndhPlayer, frames: usize) void {
        const n = @min(frames, audio.MAX_FRAMES);
        audio.machineClear(@intCast(n));
        var off: usize = 0;
        while (off < n) {
            if (!self.fireDue()) break;
            // Render up to whichever interrupt comes first.
            var block: u32 = @intCast(n - off);
            block = @min(block, self.frame_acc);
            for (self.timer_acc) |acc| if (acc != NEVER) {
                block = @min(block, acc >> 16); // whole samples until it is due
            };
            audio.machineRenderYm(@intCast(off), block);
            self.advance(block);
            off += block;
        }
        audio.machineClamp(@intCast(n));
    }

    // Run every interrupt that has come due, and re-arm it. False means the
    // tune ran away and has been stopped.
    fn fireDue(self: *SndhPlayer) bool {
        if (self.frame_acc == 0) {
            if (!self.call(sndh.PLAY, 0)) return self.derail();
            self.frames_played +%= 1;
            self.frame_acc = self.samples_per_frame;
            self.rearm(); // init/play may only now have programmed the timers
        }
        for (&self.timer_acc, 0..) |*acc, t| {
            if (acc.* == NEVER or self.timer_period[t] == 0) continue;
            const handler = timerVector(t);
            // A timer can be due more than once inside a single sample.
            while (acc.* < ONE) {
                if (handler != 0 and !callInterrupt(handler)) return self.derail();
                acc.* += self.timer_period[t];
            }
        }
        return true;
    }

    fn advance(self: *SndhPlayer, block: u32) void {
        self.frame_acc -= block;
        const ticks = block *% ONE;
        for (&self.timer_acc) |*acc| {
            if (acc.* != NEVER) acc.* -= @min(acc.*, ticks);
        }
    }

    fn derail(self: *SndhPlayer) bool {
        self.active = false;
        silence();
        return false;
    }

    /// Re-read the MFP: a timer the tune has (re)programmed gets a period in
    /// samples, and the one that drives `play` is left alone — we call that one
    /// ourselves and must not run it twice.
    fn rearm(self: *SndhPlayer) void {
        const driving: ?usize = switch (self.info.timer) {
            .a => 0,
            .b => 1,
            .c => 2,
            .d => 3,
            .vbl => null,
        };
        for (&self.timer_period, 0..) |*period, t| {
            if (driving != null and driving.? == t) {
                period.* = 0;
                self.timer_acc[t] = NEVER;
                continue;
            }
            const hz = timerHz(t);
            const was = period.*;
            period.* = if (hz <= 0) 0 else @intFromFloat(@max(
                @as(f32, ONE), // never less than one sample apart
                audio.SAMPLE_RATE / hz * @as(f32, ONE),
            ));
            if (period.* == 0) {
                self.timer_acc[t] = NEVER;
            } else if (was == 0) {
                self.timer_acc[t] = period.*; // newly started: due one period from now
            }
        }
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
        m68k_set_reg(REG_PC, IMAGE_BASE + entry); // sndh.INIT/EXIT/PLAY are image offsets

        return runUntilReturn();
    }
};

/// Most SNDH tunes in the wild are crunched. Depacking is done HERE, in the
/// 68000's own RAM, because that is where a real ST would do it: the packed
/// image is moved out of the way into the top half of RAM and depacked back
/// down to IMAGE_BASE, where the replay routine will live. Returns the
/// depacked length, or null if it will not fit or the stream is corrupt.
const SCRATCH: u32 = RAM_SIZE / 2;

fn open(len: u32) ?u32 {
    const out_len = depackers.depackedLen(ram()[0..len]) orelse return null;
    // The two regions must not overlap, and the packed copy must clear the stack.
    if (out_len == 0 or IMAGE_BASE + out_len > SCRATCH or SCRATCH + len > IMAGE_TOP) return null;
    @memcpy(ram()[SCRATCH..][0..len], ram()[0..len]);
    const image_len = depackers.depack(ram()[SCRATCH..][0..len], ram()[IMAGE_BASE..][0..out_len]) orelse return null;
    clearAround(image_len);
    return image_len;
}

/// An unpacked file: move it from $0, where it was staged, up to IMAGE_BASE.
/// The two ranges overlap once a file is over 64 KiB, so copy from the top down.
fn place(len: u32) u32 {
    std.mem.copyBackwards(u8, ram()[IMAGE_BASE..][0..len], ram()[0..len]);
    clearAround(len);
    return len;
}

/// Zero every byte of 68000 RAM that is not the image: the vector table must
/// not hold the staged file's bytes (a timer vector read there would call
/// garbage), and the heap must not hold a previous tune or the packed copy.
fn clearAround(image_len: u32) void {
    @memset(ram()[0..IMAGE_BASE], 0);
    @memset(ram()[IMAGE_BASE + image_len .. RAM_SIZE], 0);
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
