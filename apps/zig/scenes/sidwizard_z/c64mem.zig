// --------------------------------------------------------------------------
// The C64 around SID-Wizard's own 6502 player: 64 KiB of RAM, the player code and the
// playadapter variables from the 1.97 editor program (sw_player.bin, tools/sidwizard_z_player.py),
// the SID's registers as a write queue stamped with the 6502's cycle. Nothing else of a C64
// is here: the editor is Zig, only the player and the few adapter routines run on the CPU.
//
// The bus is static (cpu6502.Cpu takes a type), so this module owns the one machine's state.
// --------------------------------------------------------------------------
const cpu6502 = @import("cpu6502");

const image = @embedFile("sw_player.bin"); // blocks of [u16 addr][u16 len][bytes]
pub const RET: u16 = 0xD2FF; // a planted return address: no code runs there
const RUNAWAY: u32 = 400_000; // instructions a call may take (a tick is ~600 cycles)

pub const SidWrite = struct { cycle: u64, reg: u8, val: u8 };
pub const QCAP = 512;

// The buffers are the cart's (zg.mem at boot): a 64 KB static would be a zero-filled data segment (zero_segments).
var ram_: *[65536]u8 = undefined;
var queue_: *[QCAP]SidWrite = undefined;
var qn_: usize = 0;
var lost_: u32 = 0;
var cyc_: *const u64 = &zero;
const zero: u64 = 0;

const Bus = struct {
    pub fn read(a: u16) u8 {
        return ram_[a];
    }
    pub fn write(a: u16, v: u8) void {
        ram_[a] = v;
        if (a < 0xD400 or a >= 0xD800 or (a & 0x1F) > 0x18) return;
        if (qn_ == QCAP) {
            lost_ +%= 1;
            return;
        }
        queue_[qn_] = .{ .cycle = cyc_.*, .reg = @truncate(a & 0x1F), .val = v };
        qn_ += 1;
    }
};
const Cpu = cpu6502.Cpu(Bus);
var cpu_: Cpu = .{};

/// Give the C64 its memory: 64 KiB of RAM and room for QCAP SID writes. Once, before `reset`.
pub fn attach(ram_buf: *[65536]u8, queue_buf: *[QCAP]SidWrite) void {
    ram_ = ram_buf;
    queue_ = queue_buf;
}

pub fn ram() *[65536]u8 {
    return ram_;
}

/// SID writes made since the last `takeWrites`, oldest first.
pub fn writes() []const SidWrite {
    return queue_[0..qn_];
}
pub fn takeWrites() void {
    qn_ = 0;
}
pub fn lost() u32 {
    return lost_;
}

/// A cold C64: zeroed RAM, the player and the adapter's variables as the editor program has them.
pub fn reset() void {
    @memset(ram_, 0);
    var at: usize = 0;
    while (at + 4 <= image.len) {
        const addr = @as(usize, image[at]) | @as(usize, image[at + 1]) << 8;
        const n = @as(usize, image[at + 2]) | @as(usize, image[at + 3]) << 8;
        @memcpy(ram_[addr..][0..n], image[at + 4 ..][0..n]);
        at += 4 + n;
    }
    cpu_ = .{ .s = 0xFF };
    cyc_ = &cpu_.cycles;
    qn_ = 0;
    lost_ = 0;
}

pub const Call = struct { a: u8 = 0, x: u8 = 0, y: u8 = 0 };

/// JSR `addr` with A X Y and run until it returns (the clock runs on). Returns the cycles it took, or null when the
/// CPU stopped (a JAM) or ran away: the caller treats that as a dead player.
pub fn call(addr: u16, r: Call) ?u32 {
    cpu_.push(@truncate((RET -% 1) >> 8));
    cpu_.push(@truncate(RET -% 1));
    cpu_.a = r.a;
    cpu_.x = r.x;
    cpu_.y = r.y;
    cpu_.pc = addr;
    const t0 = cpu_.cycles;
    var n: u32 = 0;
    while (cpu_.pc != RET) : (n += 1) {
        cpu_.step();
        if (cpu_.stop != .none or n >= RUNAWAY) return null;
    }
    return @truncate(cpu_.cycles - t0);
}

/// The 6502's clock, which stamps the SID writes: the player moves it to each frame's start.
pub fn cycles() u64 {
    return cpu_.cycles;
}
pub fn waitUntil(c: u64) void {
    cpu_.cycles = @max(cpu_.cycles, c);
}
