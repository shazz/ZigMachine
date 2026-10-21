// --------------------------------------------------------------------------
// SysInfo — playing a sound file off the disk. The file is read through the
// drive into the cart's own RAM (zg.disk, a block at a time, as ST Replay
// loads its SAMPLE.RAW), checked, then handed to the audio side:
//
//   SNDH / SAP   zg.requestSongBytes: the host copies the image when it drains
//                the frame and loads it as it loads a song it fetched by name
//   PCM          zg.samplePlay at PCM_HZ: the audio side plays it on its own,
//                reading the buffer WHILE it plays (so it is stopped first
//                whenever the buffer is about to be read over)
//
// Stop: zg.sampleStop for the PCM, zg.stopSong for a song (the song bridge's
// reserved "none": the players reset, as when a program ends).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const list = @import("sound_list.zig");

/// The biggest sound file the page reads: the buffer is taken once, at init.
pub const BUF_BYTES: usize = 64 * 1024;
/// The PCM's rate: ST Replay's 12.5 KHz (st_replay_ui.zig RATES); a .RAW has no header to say.
pub const PCM_HZ: u32 = 12500;

pub const Player = struct {
    files: list.List,
    buf: []u8,

    pub fn init(self: *Player, files: anytype) void {
        self.files.scan(files);
        self.buf = zg.mem.mustAlloc(u8, BUF_BYTES);
    }

    /// Read the selected file off the disk and play it; the status says how it went.
    pub fn play(self: *Player) void {
        const e = self.files.selected() orelse return;
        self.stop(); // the PCM reads the buffer while it plays: stop it before reading over it
        self.files.status = self.load(e);
        if (self.files.status == .playing) self.files.playing = self.files.sel;
    }

    fn load(self: *Player, e: *const list.Entry) list.Status {
        const lay = zg.disk.mount() orelse return .not_found;
        const ent = zg.disk.find(lay, list.List.nameOf(e)) orelse return .not_found;
        if (ent.len > self.buf.len) return .too_big;
        const n = zg.disk.read(ent, self.buf);
        if (n != ent.len) return .not_found; // the drive ran out before the file did
        const bytes = self.buf[0..n];
        if (!list.imageOk(e.kind, bytes)) return .bad_image;
        const ok = switch (e.kind) {
            .sndh => zg.requestSongBytes(bytes, .sndh, 0),
            .sap => zg.requestSongBytes(bytes, .sap, 0),
            .pcm => zg.samplePlay(bytes, PCM_HZ, false),
        };
        return if (ok) .playing else .refused;
    }

    /// Stop what plays (nothing when nothing does).
    pub fn stop(self: *Player) void {
        const i = self.files.playing orelse return;
        switch (self.files.items[i].kind) {
            .pcm => _ = zg.sampleStop(),
            .sndh, .sap => zg.stopSong(),
        }
        self.files.playing = null;
        self.files.status = .stopped;
    }

    /// The SOUND page's keys: Up/Down select, P plays, S stops. True when taken.
    pub fn key(self: *Player, cp: u32) bool {
        switch (cp) {
            'p', 'P' => self.play(),
            's', 'S' => self.stop(),
            else => return false,
        }
        return true;
    }

    /// The pad: Up / Down select, Fire plays. True when taken.
    pub fn input(self: *Player, dir: u32) bool {
        switch (dir) {
            0 => self.files.move(-1),
            1 => self.files.move(1),
            5 => self.play(),
            else => return false,
        }
        return true;
    }
};
