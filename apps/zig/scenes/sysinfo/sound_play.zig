// --------------------------------------------------------------------------
// SysInfo — playing a sound file off the disk. The file is read through the
// drive into the cart's own RAM (zg.disk, a block at a time, as ST Replay
// loads its SAMPLE.RAW), checked, then handed to the audio side:
//
//   SNDH / SAP / XM / HIP   zg.requestSongBytes: the host copies the image when it
//                drains the frame and loads it as it loads a song it fetched by name
//   PCM          zg.samplePlay at PCM_HZ: the audio side plays it on its own,
//                reading the buffer WHILE it plays (so it is stopped first
//                whenever the buffer is about to be read over)
//
// A file stored ZX0-packed (the "ZX0!" container, as the disk's SNDH, XM and HIP are:
// the floppy is small) is read into the TOP of the buffer and depacked to its
// bottom, the two never overlapping, then checked and played as the depacked
// bytes: the machine's own job at load time, as an ST unpacked an ICE! file.
//
// Stop: zg.sampleStop for the PCM, zg.stopSong for a song (the song bridge's
// reserved "none": the players reset, as when a program ends).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const zx0 = @import("depackers").zx0;
const list = @import("sound_list.zig");

/// The biggest sound file the page reads, packed and depacked side by side: the
/// buffer is taken once, at init (the disk's XM: 18.6 KB packed, 56.5 KB depacked).
pub const BUF_BYTES: usize = 96 * 1024;
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
        const top = self.buf[self.buf.len - ent.len ..];
        if (zg.disk.read(ent, top) != ent.len) return .not_found; // the drive ran out before the file did
        const bytes = depack(top, self.buf[0 .. self.buf.len - ent.len]) catch |err| return switch (err) {
            error.TooBig => .too_big,
            error.BadImage => .bad_image,
        };
        if (!list.imageOk(e.kind, bytes)) return .bad_image;
        const ok = switch (e.kind) {
            .sndh => zg.requestSongBytes(bytes, .sndh, 0),
            .sap => zg.requestSongBytes(bytes, .sap, 0),
            .xm => zg.requestSongBytes(bytes, .xm, 0),
            .hip => zg.requestSongBytes(bytes, .hip, 0),
            .pcm => zg.samplePlay(bytes, PCM_HZ, false),
        };
        return if (ok) .playing else .refused;
    }

    /// The file as read (`file`), or what it depacks to in `room` when it is ZX0-packed.
    fn depack(file: []u8, room: []u8) error{ TooBig, BadImage }![]u8 {
        if (!zx0.isPacked(file)) return file;
        const n = zx0.depackedLen(file) orelse return error.BadImage;
        if (n > room.len) return error.TooBig;
        const got = zx0.depack(file, room[0..n]) orelse return error.BadImage;
        return room[0..got];
    }

    /// Stop what plays (nothing when nothing does).
    pub fn stop(self: *Player) void {
        const i = self.files.playing orelse return;
        switch (self.files.items[i].kind) {
            .pcm => _ = zg.sampleStop(),
            .sndh, .sap, .xm, .hip => zg.stopSong(),
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
