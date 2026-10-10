// --------------------------------------------------------------------------
// The SAP player: an Atari 8-bit tune's own 6502 code (cpu6502.zig, on the
// machine of sap_bus.zig) driving the sealed POKEY (machinePokey*). The SNDH
// player's shape: load() parses and loads, start() runs INIT, renderStereo()
// calls PLAYER every FASTPLAY scanlines and renders the POKEY between writes.
//
// The clock is the CPU's: PAL 1773447.5 Hz or NTSC 1789772.7 Hz (the SAP's
// NTSC tag), the POKEY's own. A frame is FASTPLAY x 114 cycles. Each POKEY write
// carries the cycle it was made at (sap_bus.zig), so it is heard at its sample
// inside the frame, not at the frame's start: a player sets AUDF and AUDC in
// bursts spread over its run.
//
// A call returns through a planted address (RET, in the POKEY's page: no code
// runs there). A call that does not return within RUNAWAY cycles, or a CPU
// that stops (a JAM, an unstable opcode), stops the tune; status says why.
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const cpu6502 = @import("cpu6502.zig");
const sap = @import("sap.zig");
const bus = @import("sap_bus.zig");

const Cpu = cpu6502.Cpu(bus);
const RET: u16 = 0xD2FF;
const RUNAWAY: u64 = 20 * 312 * bus.LINE; // twenty PAL frames
// The CPU clock = the POKEY's (machine/audio/pokey.zig Clock: the RTL's enables).
const PAL = [2]u64{ 100_000_000 * 901, 50805 };
const NTSC = [2]u64{ 100_000_000 * 63, 3520 };
const RATE: u64 = 44100;

pub const Stopped = enum(u8) { no, jam, unstable, runaway };

pub const SapPlayer = struct {
    active: bool = false,
    info: sap.Info = .{},
    refused: sap.Refusal = .none,
    stopped: Stopped = .no,
    stop_pc: u16 = 0,
    stop_op: u8 = 0,
    cpu: Cpu = .{},
    clock: [2]u64 = PAL,
    period: u64 = 312 * bus.LINE,
    next_call: u64 = 0, // the cycle of the next PLAYER call
    played: u64 = 0, // samples rendered since start
    head: usize = 0, // the next queued write to play

    /// The file is in song RAM at 0 (the worklet staged it).
    pub fn load(self: *SapPlayer, len: u32) bool {
        self.* = .{};
        const file = @as([*]const u8, @ptrFromInt(audio.SONG_BASE))[0..@min(len, bus.RAM_AT)];
        switch (sap.parse(file)) {
            .refused => |r| {
                self.refused = r;
                return false;
            },
            .ok => |i| self.info = i,
        }
        @memset(bus.ram(), 0);
        _ = sap.blocks(file[self.info.data..], bus.ram());
        return true;
    }

    pub fn start(self: *SapPlayer, song: u8) void {
        if (self.info.player == 0 and self.info.init == 0) return;
        const s = if (song < self.info.songs) song else self.info.defsong;
        self.clock = if (self.info.ntsc) NTSC else PAL;
        self.period = @as(u64, self.info.fastplay) * bus.LINE;
        self.cpu = .{};
        self.played = 0;
        self.head = 0;
        self.stopped = .no;
        bus.reset(!self.info.ntsc, if (self.info.ntsc) 262 else 312);
        bus.cycles = &self.cpu.cycles;
        audio.machinePokeyClock(@intFromBool(!self.info.ntsc));
        audio.machinePokeyWrite(0xF, 3); // SKCTL out of init mode, as the Atari OS leaves it
        audio.machinePokeyWrite(0x8, 0);
        self.active = switch (self.info.type) {
            .b => self.call(self.info.init, s, 0, 0),
            .c => self.call(self.info.player +% 3, 0x70, @truncate(self.info.music), @truncate(self.info.music >> 8)) and
                self.call(self.info.player +% 3, 0, s, 0),
        };
        self.next_call = (self.now() + self.period - 1) / self.period * self.period;
    }

    pub fn stop(self: *SapPlayer) void {
        if (!self.active) return; // the POKEY is left alone: no writes into other players' streams
        self.active = false;
        for (0..4) |ch| audio.machinePokeyWrite(@intCast(2 * ch + 1), 0);
    }

    fn now(self: *const SapPlayer) u64 {
        return self.cpu.cycles + bus.stall;
    }

    /// The sample a cycle is heard at.
    fn sampleOf(self: *const SapPlayer, cycle: u64) u64 {
        return @intCast(@as(u128, cycle) * RATE * self.clock[1] / self.clock[0]);
    }

    /// JSR `addr` with A X Y, until it returns to RET.
    fn call(self: *SapPlayer, addr: u16, a: u8, x: u8, y: u8) bool {
        const c = &self.cpu;
        c.push(@truncate((RET -% 1) >> 8));
        c.push(@truncate(RET -% 1));
        c.a = a;
        c.x = x;
        c.y = y;
        c.pc = addr;
        const deadline = self.now() + RUNAWAY;
        while (c.pc != RET) {
            c.step();
            if (c.stop != .none) return self.halt(if (c.stop == .jam) .jam else .unstable);
            if (self.now() > deadline) return self.halt(.runaway);
        }
        return true;
    }

    fn halt(self: *SapPlayer, why: Stopped) bool {
        self.stopped = why;
        self.stop_pc = self.cpu.pc;
        self.stop_op = self.cpu.stop_op;
        return false;
    }

    /// The next PLAYER call, at its cycle: the CPU idles to it, then runs.
    fn frame(self: *SapPlayer) void {
        const left = bus.queued - self.head; // writes a long call left for the next frame
        for (0..left) |i| bus.queue[i] = bus.queue[self.head + i];
        bus.queued = left;
        self.head = 0;
        if (self.now() < self.next_call) self.cpu.cycles = self.next_call - bus.stall;
        bus.frame_start = self.next_call;
        self.next_call += self.period;
        const at = if (self.info.type == .b) self.info.player else self.info.player +% 6;
        if (!self.call(at, 0, 0, 0)) self.stop();
    }

    pub fn renderStereo(self: *SapPlayer, frames: usize) void {
        const n: u64 = @min(frames, audio.MAX_FRAMES);
        audio.machineClear(@intCast(n));
        var off: u64 = 0;
        while (off < n and self.active) {
            while (self.head < bus.queued and self.sampleOf(bus.queue[self.head].cycle) <= self.played + off) : (self.head += 1)
                audio.machinePokeyWrite(bus.queue[self.head].reg, bus.queue[self.head].val);
            if (self.head == bus.queued and self.sampleOf(self.next_call) <= self.played + off) {
                self.frame();
                continue;
            }
            var to = self.played + n;
            if (self.head < bus.queued) to = @min(to, self.sampleOf(bus.queue[self.head].cycle));
            if (self.head == bus.queued) to = @min(to, self.sampleOf(self.next_call));
            const len = @max(to - (self.played + off), 1);
            audio.machineRenderPokey(@intCast(off), @intCast(@min(len, n - off)));
            off += @min(len, n - off);
        }
        if (off < n) audio.machineRenderPokey(@intCast(off), @intCast(n - off)); // stopped: let it ring out silent
        audio.machineClamp(@intCast(n));
        self.played += n;
    }
};
