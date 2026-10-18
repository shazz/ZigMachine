// --------------------------------------------------------------------------
// The SNDH player's native replays (digi.zig) and its three modes, which a
// screen picks with zg.requestSndhMode:
//
//   1  st      the tune's own 68000 code on Musashi
//   2  native  the recognised driver's routines in Zig: the same YM writes,
//              write for write (fpga/tests/test_sndh_native.py,
//              test_sndh_monty.py, test_sndh_wow.py). The default.
//   3  pcm     native, with the samples on a PCM channel at the timer's rate
//              instead of through the YM's volume table: the "HQ" version
//              (sndh_pcm.zig). Beat Dis and Wow Scroller; Monty answers 2.
//
// All three keep the tune's state where the 68000 keeps it, in its RAM, and
// share the SNDH player's clock and MFP: in mode 3 the timer interrupt still
// runs and still moves the sample pointer, only its three YM writes are left
// out. So a switch, either way and at any moment, carries on from the same
// sample. A tune with no native driver plays in mode 1 whatever is asked.
// --------------------------------------------------------------------------
const digi = @import("digi.zig");
const sndh = @import("sndh.zig");
const pcm = @import("sndh_pcm.zig");
const Driver = digi.Driver;
const xbtimerSet = @import("sndh_player.zig").xbtimerSet;

extern fn m68k_read_memory_8(address: c_uint) c_uint;
extern fn m68k_write_memory_8(address: c_uint, value: c_uint) void;
extern fn m68k_write_memory_16(address: c_uint, value: c_uint) void;
extern fn m68k_set_reg(reg: c_uint, value: c_uint) void;
extern fn m68k_get_reg(context: ?*anyopaque, reg: c_uint) c_uint;

pub const Mode = enum(u32) { st = 1, native = 2, pcm = 3 };

/// Off: every tune on Musashi (the oracle's reference run, audioSndhNativeEnable).
pub var enabled: bool = true;
/// What the last load found (digi.Status), for the host to report.
pub var status: digi.Status = .musashi;
/// A deliberately wrong native replay, for the oracle to prove it would catch
/// one: 1 = Beat Dis's segment end checked every interrupt, not every VBL; 2 =
/// mode 3 plays the tune's bytes raw, not the shadow (the 2026-10-11 bug); 3 =
/// Monty's play writes volume C over its drums (digi_monty_seq.zig); 4 = Wow
/// Scroller's interrupt reads its byte through Beat Dis's `addi.b #$80`; 5 = a
/// handler-only driver's steps frozen when it was armed (digi_irq.zig); 6 = the
/// stream handler's registers 9 and 10 swapped (digi_tcb3.zig); 7 = SingSong's
/// sample index read unsigned (digi_quartet.zig); 8 = the one-byte handler's pointer kept in Zig from
/// arming (digi_tcb.zig); 10 = maxYMiser's 8-bit drum routine without its
/// addi.b (digi_mym.zig); 11 = a game effect's pointer stored past its 0 byte
/// (digi_sfx.zig). Test only.
pub var mutant: u32 = 0;

var driver: ?Driver = null; // what the image is, whatever the mode
var mode: Mode = .st;
var shadow: ?pcm.Shadow = null; // mode 3's converted samples

/// The 68000's bus, for the native routines: the same functions Musashi calls.
const Bus68 = struct {
    pub inline fn read8(a: u32) u8 {
        return @truncate(m68k_read_memory_8(a));
    }
    pub inline fn write8(a: u32, v: u8) void {
        m68k_write_memory_8(a, v);
    }
    pub inline fn write16(a: u32, v: u16) void {
        m68k_write_memory_16(a, v);
    }
    pub const xbtimer = xbtimerSet; // XBIOS Xbtimer, as the SNDH player answers the trap
    pub const mem = @import("sndh_player.zig").mem; // RAM directly (digi.Access)
    /// A6, which a handler that does not save it leaves changed (digi_mix3.zig).
    pub fn setA6(v: u32) void {
        m68k_set_reg(14, v); // M68K_REG_A6
    }
    /// D7 as the interrupted code left it: a mixer whose first voice is off sums onto it (digi_sync4.zig).
    pub fn d7() u32 {
        return m68k_get_reg(null, 7); // M68K_REG_D7
    }
    /// A register the handler keeps its state in, d0-d7 then a0-a7 (digi_quartet.zig).
    pub fn getReg(n: u4) u32 {
        return m68k_get_reg(null, n);
    }
    pub fn setReg(n: u4, v: u32) void {
        m68k_set_reg(n, v);
    }
};

/// A tune was just loaded at 68000 address `base`: which driver, and the mode.
/// Returns where the 68000's heap may start: past the image and mode 3's shadow,
/// which must end by `top` (else mode 3 is not offered).
pub fn recognise(image: []const u8, base: u32, top: u32) u32 {
    forget();
    const r = digi.recognise(image, base);
    status = r.status;
    driver = r.driver;
    mode = if (driver != null and enabled) .native else .st;
    if (driver != null and !enabled) status = .disabled;
    const end = base + @as(u32, @intCast(image.len));
    if (mode == .native) {
        if (digi.pcmOf(driver.?)) |p| shadow = pcm.build(p, end, top);
    }
    return if (shadow) |sh| sh.to + (sh.hi - sh.lo) else end;
}

/// No tune: a refused load must not leave the last one's driver armed.
pub fn forget() void {
    pcm.stop();
    driver = null;
    shadow = null;
    status = .musashi;
    mode = .st;
}

/// One of INIT / EXIT / PLAY, natively if the mode says so. False: Musashi's.
pub fn call(entry: u32) bool {
    const d = driver orelse return false;
    if (d == .irq) { // its init, play and exit are the 68000's, in every mode
        if (entry == sndh.INIT) digi.irq.reinit(); // which may move the handler: armed again
        return false;
    }
    if (mode == .st) return false;
    const p = digi.pcmOf(d);
    const was = if (p) |q| digi.Access(Bus68).rd32(q.cur) else 0;
    switch (d) {
        .beat_dis => |bd| digi.beat_dis.call(Bus68, bd, entry), // its INIT ignores d0
        .wow => |wd| digi.wow.call(Bus68, wd, entry), // so does this one's
        .monty => |md| {
            digi.monty.seq.mutant = mutant;
            digi.monty.call(Bus68, md, entry); // and Monty's
        },
        .irq => unreachable, // answered above
    }
    if (entry == sndh.EXIT) {
        pcm.stop();
    } else if (mode == .pcm and (entry == sndh.INIT or digi.Access(Bus68).rd32(p.?.cur) != was)) {
        pcm.start(Bus68, p.?, shadow, mutant == 2); // a new segment
    }
    return true;
}

/// A timer interrupt to `handler`, natively if it is the driver's. False: Musashi's.
pub fn interrupt(handler: u32) bool {
    const d = driver orelse return false;
    if (mode == .st) return false;
    if (mode == .pcm) { // only a driver with a PCM path gets here: the pointer moves on
        const p = digi.pcmOf(d).?;
        if (handler != handlerOf(d)) return false;
        digi.Access(Bus68).wr32(p.cur, digi.Access(Bus68).rd32(p.cur) +% 1);
        return true;
    }
    switch (d) {
        .irq => {
            digi.irq.setMutant(mutant);
            return digi.irq.irq(Bus68, &driver.?.irq, handler);
        },
        .beat_dis => |bd| {
            if (handler != bd.handler.addr) return false;
            digi.handler.irq(Bus68, bd.handler);
            if (mutant == 1) digi.beat_dis.call(Bus68, bd, sndh.PLAY);
        },
        .wow => |wd| {
            if (handler != wd.base + digi.wow.HANDLER) return false;
            if (mutant == 4) digi.handler.irq(Bus68, .{ .addr = 0, .cur = wd.base + digi.wow.CUR, .table = wd.base + digi.wow.TABLE }) else digi.wow.irq(Bus68, wd);
        },
        .monty => |md| {
            if (handler != md.handlerAddr()) return false;
            digi.monty.irq(Bus68, md);
        },
    }
    return true;
}

fn handlerOf(d: Driver) u32 {
    return switch (d) {
        .beat_dis => |bd| bd.handler.addr,
        .wow => |wd| wd.base + digi.wow.HANDLER,
        .monty => |md| md.handlerAddr(),
        .irq => |x| digi.irq.handlerAddr(x),
    };
}

/// zg.requestSndhMode: the mode now in force, or 0 for a mode that does not
/// exist (refused: nothing changes). A tune with no native driver stays in 1.
pub fn setMode(m: u32) u32 {
    var want = if (m >= 1 and m <= 3) @as(Mode, @enumFromInt(m)) else return 0;
    const d = driver orelse return @intFromEnum(Mode.st);
    if (want == .pcm and shadow == null) want = .native; // no room for the converted samples, or no PCM path (Monty)
    if (want == mode) return @intFromEnum(want);
    if (mode == .pcm) pcm.stop();
    mode = want;
    if (want == .pcm) {
        for ([_]u16{ 8, 9, 10 }) |reg| { // the YM's volumes off: the channel plays instead
            Bus68.write16(0xFF8800, reg << 8);
            Bus68.write16(0xFF8802, 0);
        }
        pcm.start(Bus68, digi.pcmOf(d).?, shadow, mutant == 2);
    }
    return @intFromEnum(want);
}

pub fn current() u32 {
    return @intFromEnum(mode);
}
