// --------------------------------------------------------------------------
// Playing: the editor's play effects (F1, F3, Run/Stop) on the 6502 player, its SID writes on the BARD
// queue, and the live readouts the editor shows while it plays (position markers, the song time, the
// pulse-width and cut-off meters from the SID's registers). One player tick = one 50.1 Hz C64 frame;
// the library's syncPlayback runs once per tick (it counts rows on the player's own speed counter).
// Without a BARD queue (a host with no sound side) the song still plays, its ticks on the frame count.
// --------------------------------------------------------------------------
const swm = @import("swm.zig");
const dsp = @import("display.zig");
const Editor = @import("editor.zig").Editor;
const mem = @import("c64mem.zig");
const player = @import("player.zig");
const sidout = @import("sidout.zig");
const Scope = @import("scope.zig").Scope;
const follow = @import("follow.zig");

const MUTESOLO: usize = swm.music_data + swm.o_tuneheader + swm.H_MUTE; // the player reads it ($2045)
const FRAME_HZ_X1000: u32 = 50_125; // PAL: 985248 / 19656
const SCREEN_HZ_X1000: u32 = 60_000;

pub const State = enum { stopped, playing, paused };

pub const Play = struct {
    state: State = .stopped,
    mode: player.Mode = .stopped,
    out: sidout.Out = .{},
    ticks: u32 = 0, // player frames since the song started
    frame_acc: u32 = 0, // no queue: 60 Hz frames -> 50.1 Hz ticks
    sid: [25]u8 = [_]u8{0} ** 25, // the SID's registers as the player left them
    osc: Scope = .{},
    blink: i8 = 0, // blinkpos's counter: the played orderlist positions go blank for 6 of every 31 frames
    dead: bool = false, // the player's CPU stopped: the song ended itself

    /// F1 / F3: start the song (or the displayed patterns) from the top.
    pub fn start(self: *Play, ed: *Editor, mode: player.Mode) bool {
        player.start(&ed.song, .{ .mode = mode, .subtune = ed.view.selsubt, .selinst = ed.view.selinst, .curptn = ed.view.curptn1 }) catch {
            self.state = .stopped;
            return false;
        };
        _ = self.out.ensureOpen();
        self.out.begin();
        self.state = .playing;
        self.mode = mode;
        self.ticks = 0;
        self.frame_acc = 0;
        self.dead = false;
        self.sid = [_]u8{0} ** 25;
        self.osc = .{};
        self.blink = 0;
        ed.view.ordl_blink_off = false;
        self.send();
        ed.view.ptrowpos = .{ 0, 0, 0 };
        return true;
    }

    /// Shift+F3 / Run-Stop: pause, or continue where it was.
    pub fn stopOrCont(self: *Play, ed: *Editor) void {
        switch (self.state) {
            .playing => {
                player.pause(ed.view.selinst);
                self.send();
                self.state = .paused;
                ed.view.followp = false;
            },
            .paused => {
                self.out.anchor(player.frameStart()); // the sound side's clock ran on while paused
                player.unpause(self.mode);
                self.send();
                self.state = .playing;
            },
            .stopped => {},
        }
    }

    /// displayer2.inc blinkpos (PBLINKSPEED 30, ratio 6; blinking only while the song plays): reload at -1 (shown), blank at 5.
    fn blinkTick(self: *Play, ed: *Editor) void {
        self.blink -= 1;
        if (self.blink < 0) {
            self.blink = 30;
            ed.view.ordl_blink_off = false;
        } else if (self.blink == 5 and self.mode == .song) ed.view.ordl_blink_off = true;
    }

    /// Every voice's gate off and its envelope released, without the CPU (a dead player has none).
    fn hush(self: *Play) void {
        const at = player.frameStart();
        var w: [9]mem.SidWrite = undefined;
        for (0..3) |v| {
            w[v * 3] = .{ .cycle = at, .reg = @intCast(v * 7 + 5), .val = 0 };
            w[v * 3 + 1] = .{ .cycle = at, .reg = @intCast(v * 7 + 6), .val = 0 };
            w[v * 3 + 2] = .{ .cycle = at, .reg = @intCast(v * 7 + 4), .val = 8 };
        }
        for (w) |x| self.sid[x.reg] = x.val;
        self.out.send(&w);
    }

    /// A load (or anything that replaces the song) while it plays: silence it like Run/Stop does.
    pub fn halt(self: *Play, ed: *Editor) void {
        if (self.state == .playing) {
            player.pause(ed.view.selinst);
            self.send();
        }
        self.state = .stopped;
        ed.view.followp = false;
        ed.view.ordl_blink_off = false;
    }

    fn send(self: *Play) void {
        for (mem.writes()) |w| self.sid[w.reg] = w.val;
        self.out.send(mem.writes());
        mem.takeWrites();
    }

    /// Run the player's frames that are due; returns true when the song's position moved (a redraw).
    pub fn pump(self: *Play, ed: *Editor) bool {
        if (self.state != .playing) return false;
        if (!self.out.open and self.out.ensureOpen()) { // the sound side came up after the song started
            self.out.anchor(player.frameStart());
            self.out.reset_sent = false;
        }
        var ran = false;
        var n: u32 = 0;
        while (n < sidout.MAX_TICKS and self.due()) : (n += 1) {
            self.tick(ed);
            ran = true;
            if (self.state != .playing) break;
        }
        return ran;
    }

    fn due(self: *Play) bool {
        if (self.out.open) return self.out.due(player.frameStart());
        self.frame_acc += FRAME_HZ_X1000;
        if (self.frame_acc < SCREEN_HZ_X1000) return false;
        self.frame_acc -= SCREEN_HZ_X1000;
        return true;
    }

    fn tick(self: *Play, ed: *Editor) void {
        for (0..3) |c| mem.ram()[MUTESOLO + c] = ed.view.mutesolo[c];
        if (player.tick() == null) { // the CPU stopped (a JAM): the song ends itself, the notes must not hang
            self.dead = true;
            self.state = .stopped;
            self.hush();
            return;
        }
        self.ticks +%= 1;
        self.send();
        ed.syncPlayback(mem.ram(), true);
        if (ed.view.followp) follow.apply(&ed.song, &ed.view);
        self.osc.advance(&self.sid);
        self.blinkTick(ed);
    }

    /// The editor's play-runtime readouts (display.Overlay's "host presets"): song time, PW and cut-off meters.
    pub fn readouts(self: *Play, over: *dsp.Overlay) void {
        const secs = self.ticks * 1000 / FRAME_HZ_X1000;
        over.upbord_songtime = .{ bcd(secs / 60 % 100), bcd(secs % 60) };
        for (0..3) |c| over.pw_meter[c] = (self.sid[3 + 7 * c] & 0x0F) << 1 | self.sid[2 + 7 * c] >> 7;
        over.ct_meter = self.sid[0x16] >> 3;
        self.osc.trace(&self.sid, &over.scope);
    }
};

fn bcd(v: u32) u8 {
    return @intCast((v / 10) << 4 | v % 10);
}
