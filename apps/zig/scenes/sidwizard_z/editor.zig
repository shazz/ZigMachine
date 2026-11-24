//! editor.zig — Part 5 glue: one object owning the song, the view and the
//! menu/filer state, so a host has a single `key`/`render` surface. It also
//! owns the two play hooks the original editor's main loop uses:
//! `songForPlayer` (swm.toC64 into emulated C64 memory) and `playerState`
//! (the play-position variables the original displayer reads from the 6502
//! player).
//!
//! The 6502 player itself is not run here. The host loads the player image at
//! $1000, calls its initer, then calls `syncPlayback` once per frame.
//!
//! No globals, no allocator, no floats.
const std = @import("std");
const swm = @import("swm.zig");
const dsp = @import("display.zig");
const kh = @import("keys.zig");
const menu = @import("menu.zig");
const filer = @import("filer.zig");

/// The player's zeropage variables in the editor build (settings.cfg
/// PLAYER_VARS_BASEADDRESS=$10, PLAYER_FOR_ROM=0). player.asm arranges them in
/// 7-byte channel bunches; the offsets below are from that base:
///   block 0 $10..$24  FREQLO/FREQHI/PWLOGHO/PWHIGHO/WFGHOST/PTNGATE/PWEEPCNT
///   block 1 $25..$39  PACKCNT/SPDCNT/SEQPOS/PTNPOS/WFTPOS/PWTPOS/ARPSCNT
///   block 2 $3A..$4E  CURPTN/CURNOT/DPITCH/CURIFX/CURINS/CURFX2/CURVAL
///   block 3 $4F..$63  SLIDEVIB/FREQMODL/FREQMODH/VIDELCNT/VIBFREQU/VIBRACNT/TRANSP
///   block 4 $64..$78  TMPBASE/TMPPOS/ARPSPED/PKBDTRK/CURCHORD/CHORDPOS/ARPDPITCH
pub const player_base = 0x10; // PLAYER_VARS_BASEADDRESS
pub const player_stride = 7; // 7 bytes per channel
pub const off_spdcnt = 22; // block 1 + 1: $10+$16 = $26
pub const off_seqpos = 23; // block 1 + 2: $27
pub const off_ptnpos = 24; // block 1 + 3: $28
pub const off_curptn = 42; // block 2 + 0: $3A
pub const off_tmppos = 85; // block 4 + 1: $65
pub const tempo_table: usize = swm.music_data + swm.o_tempotbl; // TEMPOTBL (settings.cfg)

/// What the original displayer reads while playing (playadapter.padapter).
pub const PlayerPos = struct {
    seqpos: [3]u8, // player.SEQPOS: orderlist play position per channel
    ptnpos: [3]u8, // player.PTNPOS: pattern play position (memory offset)
    curptn: [3]u8, // player.CURPTN: current pattern per channel
    spdcnt: [3]u8, // player.SPDCNT: frame-speed counter
    tmppos: [3]u8, // player.TMPPOS: tempo-table position
};

pub const Editor = struct {
    song: swm.Song = .{},
    view: dsp.View = .{},
    startup: @import("startup.zig").State = .{ .open = false },

    /// init: a fresh editor workfile with the defaults the C64's InitTune
    /// leaves (unmuted tracks, default pattern length, subtune tempos).
    pub fn init() Editor {
        var e = Editor{};
        e.reset();
        return e;
    }

    /// The same fresh workfile in place: a cart builds its Editor on its own memory, not on the
    /// stack (a Song alone is ~34 KB) and without a struct-literal blob in the cart's data.
    pub fn reset(e: *Editor) void {
        swm.reset(&e.song);
        for (0..3) |t| e.song.header[swm.H_MUTE + t] = 0xff;
        e.song.header[swm.H_DEFLEN] = swm.default_ptn_len;
        e.view.mutesolo = .{ 0xff, 0xff, 0xff };
    }

    /// Load a .SWM file's bytes (the host did the I/O) and reset the view the
    /// way depackt + the editor's reload path leaves it. The user config
    /// (theme, key layout, device, feature switches, frame speed) survives,
    /// exactly as the C64 editor's Config bytes do across a load.
    pub fn load(self: *Editor, bytes: []const u8) !void {
        try swm.load(&self.song, bytes);
        const cfg = .{
            .confbits = self.view.confbits,
            .confbits2 = self.view.confbits2,
            .devicen = self.view.devicen,
            .themeno = self.view.themeno,
            .keybtyp = self.view.keybtyp,
            .framesp = self.view.framesp,
            .stptick = self.view.stptick,
            .cfgstat = self.view.cfgstat,
            .jammode = self.view.jammode, // a self-modified byte in the C editor: a load leaves it
        };
        self.view = .{};
        self.view.confbits = cfg.confbits;
        self.view.confbits2 = cfg.confbits2;
        self.view.devicen = cfg.devicen;
        self.view.themeno = cfg.themeno;
        self.view.keybtyp = cfg.keybtyp;
        self.view.framesp = cfg.framesp;
        self.view.stptick = cfg.stptick;
        self.view.cfgstat = cfg.cfgstat;
        self.view.jammode = cfg.jammode;
        self.view.mutesolo = .{
            self.song.header[swm.H_MUTE],
            self.song.header[swm.H_MUTE + 1],
            self.song.header[swm.H_MUTE + 2],
        };
        self.view.titledi = true; // dispaut after loading a tune
    }

    /// Save to a caller buffer; returns the byte count.
    pub fn save(self: *const Editor, buf: []u8) !usize {
        return swm.save(&self.song, buf);
    }

    pub fn key(self: *Editor, k: kh.Key) kh.Effect {
        return kh.handle(&self.song, &self.view, k);
    }

    /// Full frame: the editor, then whichever overlay is open.
    pub fn render(self: *const Editor, out: *dsp.Screen) void {
        dsp.render(&self.song, &self.view, out);
        if (self.view.menumode) menu.draw(&self.song, &self.view, out);
        if (self.view.menuprompt != menu.prompt_none) menu.drawPrompt(&self.view, out);
        if (self.view.filer.open) dsp.filerRender(&self.view, out);
    }

    /// Sprites / hidden row 26 / cursor data for the host's frame.
    pub fn overlay(self: *const Editor, over: *dsp.Overlay) void {
        dsp.overlayRender(&self.song, &self.view, over);
    }

    /// swm.toC64 into the emulated C64 image at music_data. The host
    /// still has to place the player code at $1000 and call its initer.
    pub fn songForPlayer(self: *const Editor, mem: *[65536]u8) !void {
        try swm.toC64(&self.song, mem[swm.music_data..]);
    }

    /// playerState: read the player's live variables out of emulated memory.
    /// Addresses are player_base + channel*player_stride + the offset above.
    pub fn playerState(mem: *const [65536]u8) PlayerPos {
        var p: PlayerPos = undefined;
        for (0..3) |c| {
            const base = player_base + c * player_stride;
            p.seqpos[c] = mem[base + off_seqpos];
            p.ptnpos[c] = mem[base + off_ptnpos];
            p.curptn[c] = mem[base + off_curptn];
            p.spdcnt[c] = mem[base + off_spdcnt];
            p.tmppos[c] = mem[base + off_tmppos];
        }
        return p;
    }

    /// padapter: update the displayer's play markers from the player memory.
    /// The pattern row counter advances when SPDCNT reaches the tempo-table
    /// value at TMPPOS and resets whenever PTNPOS wraps to 0.
    pub fn syncPlayback(self: *Editor, mem: *const [65536]u8, playing: bool) void {
        const p = playerState(mem);
        for (0..3) |c| {
            self.view.olstart[c] = p.seqpos[c];
            self.view.played_curptn[c] = p.curptn[c];
            const tempo = mem[tempo_table + @as(usize, p.tmppos[c])] & 0x7f;
            if (playing and tempo != 0 and tempo == p.spdcnt[c]) {
                self.view.ptrowpos[c] +%= 1;
            }
            if (p.ptnpos[c] == 0) self.view.ptrowpos[c] = 0;
        }
    }

    /// The host's directory listing for a pending need_listing effect.
    pub fn filerListing(self: *Editor, entries: []const filer.Entry, more: bool) void {
        kh.filerListing(&self.view, entries, more);
    }

    /// The host's load/save result (records fnotfnd/saverror).
    pub fn filerResult(self: *Editor, ok: bool) void {
        kh.filerResult(&self.view, ok);
    }
};
