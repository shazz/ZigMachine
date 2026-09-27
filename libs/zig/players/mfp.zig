// --------------------------------------------------------------------------
// The MFP 68901 as the SNDH player's 68000 sees it: the register file, the four
// timers' rates, and the interrupt controller in front of them (enable, mask,
// pending). Pure — no 68000, no RAM — so the gating is testable natively
// (mfp_test.zig); sndh_player.zig owns the clock and calls the handlers.
//
// Why the interrupt controller matters: a timer counting and a timer
// INTERRUPTING are two different things on an ST. A replay routine stops a
// digi the way STOS's Maestro does, by clearing Timer A's IERA/IMRA bits and
// leaving TACR running; with the controller not modelled, every timer whose
// control register ran called its handler, and Skystrike's SAMSTOP (and the
// end of a one-shot sample) left the digi playing on (docs/ports/SKYSTRIKE.md
// §9). The counters still run whatever IER/IMR say: they only gate the
// interrupt, as on the chip.
//
// What is NOT modelled: the in-service registers. The player calls a handler
// synchronously and it runs to its RTE before anything else can happen, so
// there is never a second interrupt for ISR to hold off. ISRA/B are kept as
// clear-only registers (a handler's `bclr #5,$fffa0f` reads and writes them
// correctly) that nothing ever sets.
// --------------------------------------------------------------------------

pub const SIZE: u32 = 0x40;
pub const CLOCK: f32 = 2457600.0;

/// Registers, as offsets from $FFFA00 (the MFP lives on odd addresses).
pub const IERA = 0x07;
pub const IERB = 0x09;
pub const IPRA = 0x0B;
pub const IPRB = 0x0D;
pub const ISRA = 0x0F;
pub const ISRB = 0x11;
pub const IMRA = 0x13;
pub const IMRB = 0x15;
pub const VR = 0x17; // vector register: its top nibble is the vector base
pub const TACR = 0x19;
pub const TBCR = 0x1B;
pub const TCDCR = 0x1D; // timer C in bits 4-6, timer D in bits 0-2
pub const TADR = 0x1F;
pub const TBDR = 0x21;
pub const TCDR = 0x23;
pub const TDDR = 0x25;

/// Timer control prescalers, indexed by the low 3 bits of the control register.
const PRESCALE = [8]u16{ 0, 4, 10, 16, 50, 64, 100, 200 };
/// A timer's interrupt channel number (A, B, C, D), which picks its vector and
/// its bit in the A or B half of IER/IPR/ISR/IMR. Channels 8..15 are the A
/// registers, 0..7 the B registers; a higher channel has the higher priority,
/// so this order — A, B, C, D — is also the order pending ones are delivered.
pub const CHANNEL = [4]u8{ 13, 8, 5, 4 };
/// Refuse to emulate a timer faster than this: a tune that programs a silly
/// rate must not be able to hang the audio thread.
const MAX_TIMER_HZ: f32 = 40000.0;

/// What TOS 1.04 leaves in the interrupt controller when a program starts,
/// read off Hatari after boot ($FFFA07/09/13/15): Timer C (the 200 Hz system
/// tick), the keyboard ACIA and the RS-232 interrupts enabled and unmasked;
/// Timers A, B and D OFF. A tune that wants a timer turns it on itself, as it
/// must on a real machine — which is what the tunes on the shelf do.
const IERA_TOS: u8 = 0x1E;
const IERB_TOS: u8 = 0x64;
const IMRA_TOS: u8 = 0x1E;
const IMRB_TOS: u8 = 0x64;

/// TOS leaves the vector base at $40, and tunes count on it: they install
/// their handlers at the standard addresses ($120 for Timer B, $134 for Timer A)
/// without ever writing VR themselves. Start the MFP the way a booted ST hands
/// it over, or the vectors are computed from a base of 0 and point into the
/// tune's own header.
///
/// TOS actually leaves VR = $48: the same base, in SOFTWARE end-of-interrupt
/// mode. The S bit is left clear here because in-service is not modelled (see
/// the header): the player behaves as automatic-EOI, so VR says so.
const VR_TOS_DEFAULT: u8 = 0x40;

pub const Mfp = struct {
    regs: [SIZE]u8,

    /// The MFP as TOS hands it to a program: vector base $40, the interrupt
    /// controller as TOS set it, and every timer stopped.
    pub fn reset(self: *Mfp) void {
        @memset(&self.regs, 0);
        self.regs[VR] = VR_TOS_DEFAULT;
        self.regs[IERA] = IERA_TOS;
        self.regs[IERB] = IERB_TOS;
        self.regs[IMRA] = IMRA_TOS;
        self.regs[IMRB] = IMRB_TOS;
    }

    pub fn read(self: *const Mfp, off: u32) u8 {
        return self.regs[off];
    }

    /// A CPU write. Most registers simply hold what was written; the
    /// interrupt controller's do not:
    ///  - IER: disabling a channel also drops its pending request.
    ///  - IPR / ISR: software can only CLEAR bits (write 0s); a 1 changes nothing.
    pub fn write(self: *Mfp, off: u32, value: u8) void {
        switch (off) {
            IERA, IERB => {
                self.regs[off] = value;
                self.regs[off + (IPRA - IERA)] &= value;
            },
            IPRA, IPRB, ISRA, ISRB => self.regs[off] &= value,
            else => self.regs[off] = value,
        }
    }

    /// Timer `t` (0=A..3=D) counted down to zero. Its channel goes pending if
    /// it is ENABLED; a disabled channel's timeout is lost, as on the chip.
    pub fn timeout(self: *Mfp, t: usize) void {
        const reg, const bit = channelBit(CHANNEL[t]);
        if (self.regs[IERA + reg] & bit != 0) self.regs[IPRA + reg] |= bit;
    }

    /// The highest-priority timer that is pending AND unmasked, with its
    /// pending bit cleared — the interrupt the 68000 takes next — or null.
    /// A masked channel stays pending and is delivered once it is unmasked.
    pub fn nextInterrupt(self: *Mfp) ?usize {
        for (CHANNEL, 0..) |ch, t| {
            const reg, const bit = channelBit(ch);
            if (self.regs[IPRA + reg] & self.regs[IMRA + reg] & bit != 0) {
                self.regs[IPRA + reg] &= ~bit;
                return t;
            }
        }
        return null;
    }

    /// How often timer `t` (0=A..3=D) counts down, or 0 when it is stopped.
    pub fn timerHz(self: *const Mfp, t: usize) f32 {
        const ctrl: u8 = switch (t) {
            0 => self.regs[TACR] & 0x0F,
            1 => self.regs[TBCR] & 0x0F,
            2 => (self.regs[TCDCR] >> 4) & 0x07,
            else => self.regs[TCDCR] & 0x07,
        };
        // Bit 3 is event-count mode, which counts an external signal, not the clock.
        if (ctrl == 0 or ctrl > 7) return 0;
        const data: u16 = switch (t) {
            0 => self.regs[TADR],
            1 => self.regs[TBDR],
            2 => self.regs[TCDR],
            else => self.regs[TDDR],
        };
        const count: f32 = if (data == 0) 256 else @floatFromInt(data);
        const hz = CLOCK / (@as(f32, @floatFromInt(PRESCALE[ctrl])) * count);
        return if (hz > MAX_TIMER_HZ) 0 else hz;
    }

    /// XBIOS Xbtimer's register work: program timer `t` and, when the call
    /// installs a handler, enable and unmask its interrupt — TOS's Xbtimer
    /// ends in jenabint, so a tune that starts its digidrum timer this way
    /// never touches IER/IMR itself (Mad Max's Monty digidrums).
    pub fn xbtimer(self: *Mfp, t: usize, ctrl: u8, data: u8, enable: bool) void {
        switch (t) {
            0 => {
                self.regs[TACR] = ctrl & 0x0F;
                self.regs[TADR] = data;
            },
            1 => {
                self.regs[TBCR] = ctrl & 0x0F;
                self.regs[TBDR] = data;
            },
            2 => {
                self.regs[TCDCR] = (self.regs[TCDCR] & 0x0F) | ((ctrl & 0x07) << 4);
                self.regs[TCDR] = data;
            },
            else => {
                self.regs[TCDCR] = (self.regs[TCDCR] & 0xF0) | (ctrl & 0x07);
                self.regs[TDDR] = data;
            },
        }
        if (!enable) return;
        const reg, const bit = channelBit(CHANNEL[t]);
        self.regs[IERA + reg] |= bit;
        self.regs[IMRA + reg] |= bit;
    }

    /// Where timer `t`'s vector lives: the vector base plus its channel, x4.
    pub fn vectorSlot(self: *const Mfp, t: usize) u32 {
        return ((@as(u32, self.regs[VR]) & 0xF0) | CHANNEL[t]) * 4;
    }
};

/// A channel's register half (0 = the A registers, 2 = the B registers, which
/// sit one register pair further on) and its bit there.
fn channelBit(ch: u8) struct { u32, u8 } {
    return if (ch >= 8) .{ 0, @as(u8, 1) << @intCast(ch - 8) } else .{ IERB - IERA, @as(u8, 1) << @intCast(ch) };
}
