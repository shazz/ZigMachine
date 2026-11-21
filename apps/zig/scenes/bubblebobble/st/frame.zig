// --------------------------------------------------------------------------
// The machine's frame: one 50 Hz ST frame of 313 lines x 512 cycles, run as
// the 68000 lived it. The VBL interrupt ($70) at the top, the picture's 200
// lines each ending with an MFP Timer B event (the game counts them to change
// colours mid-screen and to learn the picture is done), and the translated
// game code running in between, stopped at each event by the cycle clock.
// --------------------------------------------------------------------------
const k = @import("cpu.zig");
const io = @import("io.zig");
const tos = @import("tos.zig");
const gen = @import("../gen/dispatch.zig");

/// Where TEXT is loaded (tools/bubblebobble/st_prg.py BASE).
pub const BASE: u32 = 0x10000;
/// The joystick packet TOS hands joyvec: header, port 0, port 1.
const JOY_PACKET: u32 = 0x0E40;
/// A return address no routine has: a call from the host returns here.
const HOST_RETURN: u32 = 0x0E80;
/// An interrupt handler that runs longer than this is stopped (harness reports it).
const IRQ_MAX_CYC: u64 = 400_000;

pub var pc: u32 = BASE;
pub var frames: u64 = 0;
pub var joy: [2]u8 = .{ 0, 0 };
pub var stuck_irqs: u32 = 0;

/// Power-on: RAM cleared, the program's TEXT at BASE (relocated), the CPU at its entry.
pub fn reset(text: []const u8) void {
    @memset(k.mem, 0);
    @memcpy(k.mem[BASE..][0..text.len], text);
    k.d = .{0} ** 8;
    k.a = .{0} ** 8;
    k.a[7] = BASE - 0x100;
    k.setSr(0x0300);
    k.cy = 0;
    k.bad_pcs = 0;
    io.reset();
    io.frame_start = 0;
    tos.reset();
    pc = BASE;
    frames = 0;
    joy = .{ 0, 0 };
    stuck_irqs = 0;
}

fn runMain(until: u64) void {
    k.limit = until;
    while (k.cy < k.limit and !tos.terminated) pc = gen.dispatch(pc);
}

/// Take the interrupt whose vector is at `vec` now, and run its handler to its rte.
fn interrupt(vec: u32) void {
    const h = k.rl(vec);
    if (h == 0 or h >= k.RAM) return;
    k.exception(pc);
    pc = h;
    io.in_irq = true;
    const stop = k.cy + IRQ_MAX_CYC;
    k.limit = stop;
    while (io.in_irq and k.cy < stop and !tos.terminated) pc = gen.dispatch(pc);
    if (io.in_irq) stuck_irqs += 1;
    io.in_irq = false;
}

/// Run one routine as a subroutine of the host (a TOS callback), registers kept.
fn call(addr: u32) void {
    const saved_d = k.d;
    const saved_a = k.a;
    const sr = k.getSr();
    k.push32(HOST_RETURN);
    var p = addr;
    const stop = k.cy + IRQ_MAX_CYC;
    k.limit = stop;
    while (p != HOST_RETURN and k.cy < stop) p = gen.dispatch(p);
    k.d = saved_d;
    k.a = saved_a;
    k.setSr(sr);
}

/// A joystick changed (bit 0 up, 1 down, 2 left, 3 right, 7 fire): the IKBD's
/// event packet, delivered to the joyvec the game installed.
pub fn setJoystick(port: u1, state: u8) void {
    if (joy[port] == state) return;
    joy[port] = state;
    k.wb(JOY_PACKET, 0xFE + @as(u8, port));
    k.wb(JOY_PACKET + 1, joy[0]);
    k.wb(JOY_PACKET + 2, joy[1]);
    io.kbd_byte = state;
    const vec = k.rl(tos.KBDVECS + 0x18);
    if (vec == 0) return;
    const a0 = k.a[0];
    k.a[0] = JOY_PACKET;
    call(vec);
    k.a[0] = a0;
}

/// One 50 Hz frame.
pub fn runFrame() void {
    const f0 = io.frame_start;
    io.shown_base = io.videoBase();
    io.raster_n = 0;
    interrupt(0x70);
    runMain(f0 + io.TOP_LINE * io.LINE_CYC);
    io.palette_top = io.palette;
    for (0..io.LINES) |l| {
        runMain(f0 + (io.TOP_LINE + l) * io.LINE_CYC + 400);
        if (io.timerBLine()) interrupt(0x120);
    }
    runMain(f0 + io.FRAME_CYC);
    io.frame_start = f0 + io.FRAME_CYC;
    if (k.cy > io.frame_start + io.FRAME_CYC) k.cy = io.frame_start; // a stuck handler: resync
    frames += 1;
}
