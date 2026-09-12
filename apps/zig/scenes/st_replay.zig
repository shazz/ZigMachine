// --------------------------------------------------------------------------
// ST Replay — a homage to Microdeal's 8-bit sampler for the Atari ST, rebuilt on
// ZigMachine. The original is not a windowed GEM application: it is a single
// full-screen medium-res panel driven entirely from the keyboard, with a status
// strip and a waveform box. st_replay_ui.zig holds that layout (measured off a
// screenshot of the real 3.01 screen); this file is the state, the keyboard and
// the audio bridge.
//
// NOTE: the original's title line carries its authors' own copyright notice.
// This is a reimplementation, not their program, so it names itself and credits
// the original instead of reproducing that notice.
//
// Select in apps/zig/floppy.zig.
// --------------------------------------------------------------------------
const std = @import("std");

const zg = @import("zigos");
const disk = @import("zigos").disk;
const ZigOS = zg.ZigOS;
const Blitter = zg.Blitter;
const hw = @import("hardware");
// The app talks to the ROM ONLY through its flat ABI — no @import("rom"),
// which is the ROM's internals and stops being reachable once GEM moves into
// rom.wasm (Phase 2 step 2.2). See rom/sdk/rom.zig.
const rom = @import("rom_sdk");
const ui = @import("st_replay_ui.zig");
const draw = @import("st_replay_draw.zig");
const Rect = rom.Rect;

const WAVE_LEN: usize = 1280; // display resolution (host downsamples the .raw into it)
// How long to sweep the playhead when the host has not told us the sample's real
// length. Only a display fallback — it never gates playback.
const FALLBACK_SECS: f32 = 1.0;
const SILENCE: u8 = 0; // .raw samples are SIGNED 8-bit, so silence is zero
// The sample lives in the machine's own RAM. The drive hands over blocks; the
// program does the loading, the downsampling and the playback itself.
// Sample RAM. The machine has 2 MB, but the CART's window is what this buffer
// competes for: [0x100000,0x300000) also holds the 384 KB stack and every static
// in GEM, the boot ROM and this app. A megabyte overran it and the machine
// trapped on boot (caught by apps/gem_headless.mjs), so the sampler takes half a
// meg.
//
// It was never GEM's statics: `gem.Desktop` is 2332 bytes. It was one line in
// gem_desktop.zig — `self.* = .{}` — whose comptime-known `Demo{}` embedded THIS
// buffer, so the linker emitted a second 526 KB blob of zeros to memcpy over the
// global. Removing that gave 514 KB back and the megabyte fits, with ~590 KB still
// free by hwRamFree()'s own count (shown on the panel, gated by build.sh).
const MAX_PCM: usize = 1024 * 1024;
const FRAME_HZ: u32 = 60;

// The sample itself, in machine RAM. Module-level, NOT a field of App — which is
// about safety, not size: a struct carrying a megabyte array is a landmine, because
// any `x = .{}` on it makes the linker materialise a WHOLE SECOND copy as a data
// segment. That is precisely what `self.* = .{}` in gem_desktop.zig did, and it
// cost 517 KB of the cart's RAM window until 2026-09-12. Out here, it cannot
// happen again.
//
// It does NOT shrink the wasm. The cart imports its memory (build.zig), and
// wasm-lld cannot assume imported memory is zeroed, so it materialises .bss as
// explicit zero data segments regardless — the megabyte is in the file either
// way (measured: file size tracks MAX_PCM 1:1). Serve the carts gzipped if that
// matters; a megabyte of zeros compresses to nothing.
//
// `undefined` + an explicit memset in init() rather than a zero initialiser,
// because the loader swaps carts over ONE shared memory: never assume a fresh
// cart's RAM is clean. Same reason every scalar in init() is set, not assumed.
var pcm: [MAX_PCM]u8 = undefined;


pub const App = struct {
    blit: Blitter = .{},
    // Handles into the ROM, not structures of our own: the toolkit's state lives
    // on the ROM's side of the ABI (and, after step 2.2, in the ROM's RAM window).
    g: rom.Gui = .{},
    dialog: rom.Dialog = .{},
    fsel: rom.FileSel = .{}, // GEM's ITEM SELECTOR, opened by "Load from disc"
    sample: [WAVE_LEN]u8 = [_]u8{SILENCE} ** WAVE_LEN, // the display view, built here
    pos: usize = 0, // how far the replay has fed the audio ring
    rate: usize = 2, // index into ui.RATES; the real thing boots at 10 KHz
    playing: bool = false,
    looping: bool = false,
    marked: bool = false,
    low: u32 = 0,
    high: u32 = 0,
    // The REAL length of the loaded sample in bytes. The host downsamples it
    // into `sample` for display, so the display buffer's size says nothing about
    // the sample — every count the panel reports comes from here.
    bytes: u32 = 0,
    hz: u32 = 0, // its playback rate, so the view has a real TIME axis
    playhead: f32 = 0,
    wants_quit: bool = false,

    // "Load from disc": GEM's ITEM SELECTOR, listing what is ACTUALLY on the
    // mounted floppy — the FAT is walked here, by the machine, not handed over by
    // the page.
    fn openSelector(self: *App) void {
        self.fsel.show("*.RAW");
        const lay = disk.mount() orelse return self.dlg("Load from disc", "No disc in drive A:.");
        var i: u16 = 0;
        while (i < lay.count) : (i += 1) {
            const ent = disk.entryAt(lay, i) orelse continue;
            const name = std.mem.sliceTo(&ent.name, 0);
            if (std.mem.endsWith(u8, name, ".RAW")) self.fsel.add(name);
        }
    }

    // Load a file off the mounted floppy into machine RAM, through the drive, one
    // block at a time — then build the display view from it here. Nothing about
    // the sample passes through the page.
    fn loadFromDisc(self: *App, name: []const u8) void {
        const lay = disk.mount() orelse return self.dlg("Load from disc", "No disc in drive A:.");
        const ent = disk.find(lay, name) orelse return self.dlg("Load from disc", "File not found.");
        self.stop();
        const n = disk.read(ent, &pcm);
        @memset(pcm[n..], SILENCE);
        self.bytes = @intCast(n);
        self.low = 0;
        self.high = self.bytes;
        self.pos = 0;
        self.buildView();
        if (n < ent.len) self.dlg("Load from disc", "Sample truncated to fit RAM.");
    }

    fn dlg(self: *App, title: []const u8, msg: []const u8) void {
        self.dialog.alert(title, msg);
    }

    // Downsample the loaded PCM into the display buffer. Nothing else — an earlier
    // bulk edit pasted init()'s state reset in here, which zeroed `bytes` and made
    // every load look as though it had silently failed.
    fn buildView(self: *App) void {
        @memset(&self.sample, SILENCE);
        if (self.bytes == 0) return;
        var i: usize = 0;
        while (i < WAVE_LEN) : (i += 1) {
            const si = i * @as(usize, self.bytes) / WAVE_LEN;
            self.sample[i] = pcm[si];
        }
    }

    // Is there anything to play? The host reports the byte count, but that is an
    // extra ABI call that an older host (or a cached loader) may not make — so
    // fall back to asking the display buffer itself. Silence is SILENCE; anything
    // else means a sample arrived.
    fn loaded(self: *const App) bool {
        if (self.bytes > 0) return true;
        for (self.sample) |v| {
            if (v != SILENCE) return true;
        }
        return false;
    }

    // Seconds of audio in the loaded sample.
    fn duration(self: *const App) f32 {
        const hz = ui.RATES[self.rate]; // replaying faster makes the sample shorter
        if (self.bytes == 0 or hz == 0) return FALLBACK_SECS; // count not reported
        return @as(f32, @floatFromInt(self.bytes)) / @as(f32, @floatFromInt(hz));
    }

    pub fn init(self: *App, os: *ZigOS) void {
        const fb = &os.lfbs[0];
        // A STANDALONE cart since step 2.3b: GEM no longer contains this app, the
        // host instantiates it off the floppy. So the plane is ours to bring up —
        // nobody has enabled it or allocated its buffer for us.
        fb.is_enabled = true;
        fb.setMediumPlane(); // the 640-wide buffer the medium layout needs
        // The ROM owns the drawing context (and brings its own blitter) — we hold
        // a handle. close() first: a cart swap reuses the memory, so a stale
        // handle may be sitting in these fields, and leaking the ROM's handles
        // exhausts its tables until every call silently does nothing.
        self.g.close();
        self.dialog.close();
        self.fsel.close();
        self.g = rom.Gui.open(os, fb, ui.SW, ui.SH);
        // The app owns the whole screen: put the plane in MEDIUM res (the layout
        // is 640 wide) and install both palettes itself rather than inheriting
        // whatever the desktop left behind.
        fb.setResMedium();
        rom.installPalette(@intCast(@intFromPtr(fb)));
        ui.installPalette(fb);
        self.wants_quit = false;
        self.playing = false;
        // The cart lives in `undefined` memory until init, so the display buffer
        // has to be silenced explicitly — otherwise the leftover bytes read as a
        // loaded sample (SILENCE is 128, not 0).
        // The cart lives in `undefined` memory until init: every flag has to be
        // set, not assumed. A garbage `fsel.active` swallowed the keyboard.
        self.fsel = rom.FileSel.open();
        self.dialog = rom.Dialog.open();
        self.playhead = 0;
        self.pos = 0;
        self.bytes = 0;
        self.low = 0;
        self.looping = false;
        self.marked = false;
        @memset(&self.sample, SILENCE);
        @memset(&pcm, SILENCE); // .bss, and the cart swap reuses memory — see above
        self.rate = 2; // 10 KHz, as the original boots
        self.high = self.bytes;
    }

    // Everything the screen needs to draw itself, and nothing else.
    fn view(self: *const App) draw.View {
        return .{
            .rate = self.rate,
            .looping = self.looping,
            .marked = self.marked,
            .playing = self.playing,
            .playhead = self.playhead,
            .low = self.low,
            .high = self.high,
            .bytes = self.bytes,
            .free = hw.hwRamFree(),
            .sample = &self.sample,
        };
    }

    // The host's cart-swap protocol (see demo_main.zig): 4 = return to the OS.
    // An app launched from GEM quits back to GEM, not to the menu — the disk it
    // came from is still in the drive, and -1 would drop the user at a menu they
    // never came from.
    pub fn pollCart(self: *App) i32 {
        return if (self.wants_quit) 4 else 0;
    }

    pub fn pointer(self: *App, x: i32, y: i32, buttons: u32) void {
        self.g.setPointer(x, y, buttons);
    }

    // The whole program is the keyboard. Unknown keys are ignored, as in TOS.
    pub fn key(self: *App, cp: u32) void {
        if (self.fsel.active()) return self.fsel.key(cp); // the selector owns typing
        if (self.dialog.active()) return; // a dialog owns input while it is up
        if (cp >= ui.K_F1 and cp < ui.K_F1 + ui.ROWS) return self.fkey(cp - ui.K_F1);
        switch (cp) {
            'q', 'Q' => self.looping = !self.looping,
            'l', 'L' => self.openSelector(),
            's', 'S' => self.dialog.alert("Save to disc", "The disc is read-only."),
            'x', 'X' => { // eXit: never leave the sound running behind us
                self.stop();
                self.wants_quit = true;
            },
            'r', 'R' => self.reverse(),
            'w', 'W' => self.wipe(),
            ui.K_UNDO => { // RESET cursors
                self.low = 0;
                self.high = self.bytes;
                self.marked = false;
            },
            // Space is the transport: play if stopped, stop if playing. Esc only
            // ever STOPS — a panic key should never start something.
            ' ' => if (self.playing) self.stop() else self.play(),
            ui.K_ESC => self.stop(),
            else => {},
        }
    }

    // Arrow keys walk the selection — the highlighted replay rate — the way the
    // function keys jump straight to one. Wraps, so holding a direction cycles.
    pub fn input(self: *App, dir: u32) void {
        if (self.dialog.active()) return;
        switch (dir) {
            0 => self.rate = (self.rate + ui.RATE_ROWS - 1) % ui.RATE_ROWS, // up
            1 => self.rate = (self.rate + 1) % ui.RATE_ROWS, // down
            else => {},
        }
    }

    // f1..f8 pick the replay rate; f10 replays.
    fn fkey(self: *App, n: usize) void {
        if (n < ui.RATE_ROWS) {
            self.rate = n;
        } else switch (n) {
            9 => self.play(), // f10 = Replay
            else => {}, // f9 Magnify needs a zoomable view we do not have yet
        }
    }

    // Nothing to replay until a sample has been loaded — Replay is a no-op on an
    // empty machine rather than a silent "playing" state.
    fn play(self: *App) void {
        if (!self.loaded()) return;
        self.playing = true;
        self.playhead = 0;
        self.pos = 0;
        zg.audioStreamStart(@floatFromInt(ui.RATES[self.rate])); // the speaker, nothing more
    }
    fn stop(self: *App) void {
        self.playing = false;
        self.pos = 0;
        zg.audioStreamStop();
    }
    // Wipe area: silence the sample itself. It must NOT touch the dialogs or the
    // rest of the app's state — an editor command edits, it does not reboot.
    fn wipe(self: *App) void {
        @memset(&self.sample, SILENCE);
        @memset(&pcm, SILENCE);
        self.bytes = 0;
        self.low = 0;
        self.high = 0;
        self.marked = false;
        self.stop();
    }

    fn reverse(self: *App) void {
        var i: usize = 0;
        while (i < WAVE_LEN / 2) : (i += 1) {
            const t = self.sample[i];
            self.sample[i] = self.sample[WAVE_LEN - 1 - i];
            self.sample[WAVE_LEN - 1 - i] = t;
        }
    }

    pub fn update(self: *App, os: *ZigOS, dt: f32) void {
        _ = os;
        self.g.beginFrame();
        self.clicks();
        _ = dt;
        if (self.playing) self.feed();
    }

    // One frame of replay: hand the speaker the next slice of OUR sample. At the
    // selected rate that is rate/60 bytes a frame — the pace is the machine's, so
    // f1..f6 change the pitch simply by changing how much we feed.
    fn feed(self: *App) void {
        const chunk: usize = @as(usize, ui.RATES[self.rate]) / FRAME_HZ;
        const end = @min(self.pos + chunk, @as(usize, self.bytes));
        if (end > self.pos) {
            zg.audioFeed(pcm[self.pos..end]);
            self.pos = end;
        }
        self.playhead = @as(f32, @floatFromInt(self.pos)) /
            @as(f32, @floatFromInt(@max(self.bytes, 1))) * @as(f32, WAVE_LEN);
        if (self.pos < self.bytes) return;
        if (self.looping) self.play() else self.playing = false;
    }

    // Every binding row is also a BUTTON: a click on it dispatches the row's own
    // key, so mouse and keyboard cannot drift apart (the frequency rows behaved
    // this way already; now the whole panel does).
    fn clicks(self: *App) void {
        if (!self.g.edge() or self.dialog.active() or self.fsel.active()) return;
        var row: usize = 0;
        while (row < ui.ROWS) : (row += 1) {
            const y = ui.rowY(row);
            if (self.g.hit(ui.bindingRect(ui.LEFT[row], ui.COL_EQ[0], y))) return self.key(ui.LEFT[row].cp);
            if (self.g.hit(ui.bindingRect(ui.RIGHT[row], ui.COL_EQ[2], y))) return self.key(ui.RIGHT[row].cp);
        }
        for (ui.MID, 0..) |b, i| {
            if (self.g.hit(ui.bindingRect(b, ui.COL_EQ[1], ui.rowY(ui.MID_ROW0 + i)))) return self.key(b.cp);
        }
    }

    pub fn render(self: *App, os: *ZigOS, dt: f32) void {
        _ = os;
        _ = dt;
        const g = self.g; // a handle, copied by value — there is nothing to alias
        draw.screen(g, self.view());
        _ = self.dialog.process(g);
        switch (self.fsel.process(g)) {
            .ok => {
                // chosen() copies into OUR buffer: a slice cannot cross the ABI,
                // and a pointer into the ROM's storage would be a lifetime we
                // could not reason about. It also keeps the copy loadFromDisc
                // needs anyway, since that reopens dialogs.
                var pick: [16]u8 = undefined;
                const name = self.fsel.chosen(&pick);
                if (name.len > 0) self.loadFromDisc(name);
            },
            else => {},
        }
        g.endFrame();
    }

};
