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
                player.unpause(self.mode);
                self.send();
                self.state = .playing;
            },
            .stopped => {},
        }
    }

    fn send(self: *Play) void {
        for (mem.writes()) |w| self.sid[w.reg] = w.val;
        self.out.send(mem.writes());
        mem.takeWrites();
    }

    /// Run the player's frames that are due; returns true when the song's position moved (a redraw).
    pub fn pump(self: *Play, ed: *Editor) bool {
        if (self.state != .playing) return false;
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
        if (player.tick() == null) {
            self.dead = true;
            self.state = .stopped;
            self.send();
            return;
        }
        self.ticks +%= 1;
        self.send();
        ed.syncPlayback(mem.ram(), true);
    }

    /// The editor's play-runtime readouts (display.Overlay's "host presets"): song time, PW and cut-off meters.
    pub fn readouts(self: *const Play, over: *dsp.Overlay) void {
        const secs = self.ticks * 1000 / FRAME_HZ_X1000;
        over.upbord_songtime = .{ bcd(secs / 60 % 100), bcd(secs % 60) };
        for (0..3) |c| over.pw_meter[c] = (self.sid[3 + 7 * c] & 0x0F) << 1 | self.sid[2 + 7 * c] >> 7;
        over.ct_meter = self.sid[0x16] >> 3;
    }
};

fn bcd(v: u32) u8 {
    return @intCast((v / 10) << 4 | v % 10);
}
