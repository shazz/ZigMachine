// --------------------------------------------------------------------------
// The XM sequencer (xm.zig's player): one tick at a time. The row's notes and
// row effects on the first tick, the running effects on the others, then every
// tick the channels' steps and gains are applied to the mixer. Row to row,
// order to order: B jumps, D breaks, E-pattern-delay repeats a row. Like the
// MOD sequencer (mod_rows.zig), it touches no chip; xm_chip.zig does that.
// --------------------------------------------------------------------------
const xp = @import("xm_pattern.zig");
const xt = @import("xm_tables.zig");
const xv = @import("xm_voice.zig");
const inst = @import("xm_instr.zig");
const effects = @import("xm_effects.zig");
const fmt = @import("xm_format.zig");
const XmPlayer = @import("xm.zig").XmPlayer;

/// One sequencer tick: the row on tick 0 (unless an E-pattern-delay repeats it),
/// the running effects on the others, then every channel's step and gain.
pub fn tick(p: *XmPlayer) void {
    if (!p.active) return;
    const n: usize = p.hdr.channels;
    if (p.tick == 0) {
        if (!p.repeat) processRow(p);
        p.repeat = false;
    } else {
        for (0..n) |ch| effects.tickEffect(p, ch);
    }
    // The envelope moves on every tick, tick 0 included (FT2): it is read first,
    // so a note's first tick plays its envelope's first point.
    for (0..n) |ch| {
        effects.apply(p, ch);
        effects.tickEnvelope(p, ch);
    }
    p.tick += 1;
    if (p.tick >= p.speed) {
        p.tick = 0;
        advanceRow(p);
    }
}

/// Start the note of channel `ch` at `note` (1..96) with its instrument.
/// Silent (no change) with no instrument, or an instrument with no samples.
pub fn trigger(p: *XmPlayer, ch: usize, note: u8) void {
    const c = &p.chan[ch];
    const ins = instrumentOf(p, c.inst) orelse return;
    if (ins.count == 0) return;
    const sidx = @as(u16, ins.first) + ins.map[note - 1];
    const s = &p.tabs.samps[sidx];
    c.mix = .{ .active = s.len > 0, .sample = sidx };
    c.semi = @as(i32, note) - 1 + s.relnote;
    c.ft = s.finetune;
    c.base_period = xt.periodOf(c.semi, c.ft, p.hdr.linear);
    c.period = c.base_period;
    c.vib_pos = 0;
    xv.keyOn(c);
}

/// An instrument number resets the volume to its sample's and restarts the
/// envelope (FT2), with or without a note; a note alone keeps the volume.
fn resetInstrument(p: *const XmPlayer, c: *xv.Chan) void {
    const ins = instrumentOf(p, c.inst) orelse return;
    if (ins.count == 0) return;
    c.vol = p.tabs.samps[c.mix.sample].volume;
    xv.keyOn(c);
}

/// Note 97 or Kxx: key-off through the channel's instrument envelope.
pub fn keyOff(p: *const XmPlayer, c: *xv.Chan) void {
    const ins = instrumentOf(p, c.inst) orelse {
        c.key_on = false;
        return;
    };
    xv.keyOff(c, &ins.vol);
}

fn instrumentOf(p: *const XmPlayer, one_based: u8) ?*const inst.Instrument {
    if (one_based == 0 or one_based > p.hdr.num_instruments) return null;
    return &p.tabs.insts[one_based - 1];
}

/// The row's cells, then each channel's note and effects in turn.
fn processRow(p: *XmPlayer) void {
    var cells: [fmt.MAX_CH]xp.Cell = undefined;
    readCells(p, &cells);
    for (0..p.hdr.channels) |ch| rowChannel(p, ch, cells[ch]);
}

/// A note starts (or, under 3xx / 5xx, is only the portamento's target), then the
/// instrument number resets the volume, then the volume column and the row
/// effect take their say, as FT2 orders them.
fn rowChannel(p: *XmPlayer, ch: usize, cell: xp.Cell) void {
    const c = &p.chan[ch];
    c.eff = cell.eff;
    c.param = effects.memoParam(c, cell.eff, cell.param);
    if (cell.inst != 0) c.inst = cell.inst;
    if (cell.note == 97) {
        keyOff(p, c);
    } else if (cell.note >= 1 and cell.note <= 96) {
        if (cell.eff == 3 or cell.eff == 5) {
            setTarget(p, c, cell.note);
        } else if (cell.eff == 0xE and cell.param >> 4 == 0xD) {
            c.pending = cell.note;
        } else {
            trigger(p, ch, cell.note);
        }
    }
    if (cell.inst != 0 and cell.note != 97) resetInstrument(p, c);
    c.vcol = cell.vol;
    effects.volumeColumnRow(c);
    effects.rowEffect(p, ch);
}

fn setTarget(p: *const XmPlayer, c: *xv.Chan, note: u8) void {
    const ins = instrumentOf(p, c.inst) orelse return;
    if (ins.count == 0) return;
    const s = &p.tabs.samps[@as(u16, ins.first) + ins.map[note - 1]];
    c.target = xt.periodOf(@as(i32, note) - 1 + s.relnote, s.finetune, p.hdr.linear);
}

/// Read the row at p.order_pos / p.row. The cache holds where the last row read
/// ended, so a row read straight after the one before it costs nothing extra.
fn readCells(p: *XmPlayer, cells: *[fmt.MAX_CH]xp.Cell) void {
    const pat = p.hdr.orders[p.order_pos];
    const info = p.pats[pat];
    if (info.end == info.off) { // FT2 saves an empty pattern with no packed data
        @memset(cells, .{});
        return;
    }
    const bytes = p.data[0..info.end];
    var off: usize = info.off;
    var r: u16 = 0;
    if (p.cache_pat == pat and p.cache_row <= p.row) {
        off = p.cache_off;
        r = p.cache_row;
    }
    while (r < p.row) : (r += 1) off = xp.readRow(bytes, off, p.hdr.channels, cells);
    off = xp.readRow(bytes, off, p.hdr.channels, cells);
    p.cache_pat = pat;
    p.cache_row = p.row + 1;
    p.cache_off = off;
}

/// The next row, or the jump, break or order step that replaces it. A row that
/// an E-pattern-delay asked to repeat is only counted down.
fn advanceRow(p: *XmPlayer) void {
    if (p.row_delay > 0) {
        p.row_delay -= 1;
        p.repeat = true;
        return;
    }
    if (p.jump_pos >= 0) {
        p.order_pos = @intCast(p.jump_pos);
        p.row = if (p.break_row >= 0) @intCast(p.break_row) else 0;
    } else if (p.break_row >= 0) {
        p.row = @intCast(p.break_row);
        nextOrder(p);
    } else {
        p.row += 1;
        if (p.row >= rowsOf(p)) {
            p.row = 0;
            nextOrder(p);
        }
    }
    p.jump_pos = -1;
    p.break_row = -1;
    wrapOrder(p);
    if (p.row >= rowsOf(p)) p.row = 0;
}

/// A jump past the song, or a step off its end, starts again at the restart order.
fn wrapOrder(p: *XmPlayer) void {
    if (p.order_pos >= p.hdr.song_len) p.order_pos = @intCast(p.hdr.restart % p.hdr.song_len);
}

fn rowsOf(p: *const XmPlayer) u16 {
    return p.pats[p.hdr.orders[p.order_pos]].rows;
}

fn nextOrder(p: *XmPlayer) void {
    p.order_pos +%= 1;
    wrapOrder(p);
}
