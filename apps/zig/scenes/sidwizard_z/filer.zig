//! filer.zig — the file dialog's logic (Part 4, menu.inc filedialog/filenamer).
//! The original opens a KERNAL directory channel and reads names itself; the
//! native editor never does I/O, so the host hands over a directory listing
//! (filer.setListing) and performs the load/save the dialog asks for.
//!
//! What is ported here: the three sub-windows (filename typer, author-info
//! typer, file selector), TAB cycling, the selector's cursor arithmetic,
//! filename/author typing (home/insert/backspace/cursors), the extension
//! append of regname, and the RETURN/STOP outcomes. What is not: the KERNAL
//! OPEN/CHRIN directory reader and the on-screen file list painting (the host
//! owns both; the list data is what matters).
//!
//! No globals, no allocator, no floats.
const std = @import("std");

// -- settings.cfg filer limits ------------------------------------------------
pub const max_name = 12; // maxnamelen
pub const ext_len = 4; // extlen (with the dot)
pub const author_len = 40; // authorilen
pub const columns = 3; // namecolums
pub const page_rows = 19; // filelistheight
pub const max_files = page_rows * columns; // filelstmax

/// Which dialog the menu row asked for (menu.inc filedialog's extension).
pub const Kind = enum { tune, instrument, config };
pub const Mode = enum { load, save };

/// filerwindow: 0 filename typer, 1 author-info typer, 2 file selector.
pub const Window = enum { name_typer, author_typer, selector };

/// The filer's error line (nodevicep/fnotfound/vermismatch/saveerror).
pub const Status = enum { ok, no_device, not_found, version, save_error };

/// One directory entry as the host read it (ASCII name without extension).
pub const Entry = struct {
    name: [max_name]u8 = [_]u8{' '} ** max_name,
    len: u8 = 0,
    blocks: u16 = 0,
};

/// regname's output: the typed name plus the dialog's extension.
pub const Name = struct {
    buf: [max_name + ext_len]u8 = [_]u8{0} ** (max_name + ext_len),
    len: u8 = 0,
};

pub const Action = union(enum) {
    none,
    redraw,
    need_listing, // host: read the directory again and call setListing
    load: Name,
    save: Name,
    close, // STOP/ESC: back to the editor without a file operation
};

/// One key as keys.zig maps the C64 matrix onto the filer. There is no
/// separate up/left: the C64 sends CRSR↓/CRSR→ and Shift reverses them
/// (fiselLR/fcurbwd read `shiftsi`).
pub const Key = union(enum) {
    none, // keychar 0 (C= key etc.)
    char: u8, // ASCII/screen-code character to type
    down,
    right,
    tab,
    ret,
    stop,
    dir, // F1: re-read the directory
    page, // F3: next page of the directory
    home,
    insert,
    backspace,
};

pub const State = struct {
    open: bool = false,
    kind: Kind = .tune,
    mode: Mode = .load,
    window: Window = .name_typer,
    editauth: bool = false, // author-info typer enabled (tune save)
    auto_dir: bool = false, // Config.confbits2 bit0: read the directory for a save
    count: u8 = 0, // filecnt
    sel: u8 = 0, // compzvar2: selected entry
    col: u8 = 0, // compzvar3: selector column
    name: [max_name]u8 = [_]u8{' '} ** max_name, // filenamp
    name_pos: u8 = 0, // compzvar2 while the typer is active
    author: [author_len]u8 = [_]u8{' '} ** author_len, // authorip
    author_pos: u8 = 0, // compzvar4-side cursor
    status: Status = .ok,
    more: bool = false, // dirready == 0: another page may exist
    entries: [max_files]Entry = [_]Entry{.{}} ** max_files,
};

fn ext(kind: Kind) [ext_len]u8 {
    return switch (kind) {
        .tune => ".SWM".*,
        .instrument => ".SWI".*,
        .config => ".CFG".*,
    };
}

fn pad(dst: []u8, text: []const u8) void {
    @memset(dst, ' ');
    const n = @min(dst.len, text.len);
    @memcpy(dst[0..n], text[0..n]);
}

/// filedialog + defawin: start the dialog. A load always wants the directory;
/// a save only when the auto-directory config bit is set (otherwise the name
/// typer is shown and the user types the name).
pub fn begin(st: *State, kind: Kind, mode: Mode, editauth: bool, auto_dir: bool, author: []const u8) Action {
    st.* = .{
        .open = true,
        .kind = kind,
        .mode = mode,
        .editauth = editauth,
        .auto_dir = auto_dir,
    };
    pad(&st.author, author);
    if (mode == .load or auto_dir) {
        st.more = true;
        return .need_listing;
    }
    return .none;
}

/// The host's directory read (readdir/listfil): names without the extension.
/// An empty listing is the original's empty selector: the typer stays active.
pub fn setListing(st: *State, entries: []const Entry, more: bool) void {
    st.count = @intCast(@min(entries.len, max_files));
    for (0..st.count) |i| st.entries[i] = entries[i];
    st.sel = 0;
    st.col = 0;
    st.more = more;
    st.status = .ok;
    if (st.mode == .load and st.count > 0) {
        st.window = .selector; // loader prefers the selector (defawin)
        selectName(st);
    }
}

/// The host's answer after it tried the load/save the dialog asked for.
/// fnotfnd/saverror show the message and return to the menu; the dialog itself
/// is already closed by then, so this only records the status.
pub fn finish(st: *State, ok: bool) void {
    st.open = false;
    st.status = if (ok) .ok else switch (st.mode) {
        .load => .not_found,
        .save => .save_error,
    };
}

/// diselcu/fiselLR: the selector cursor also writes the chosen name into
/// filenamp, so RETURN can register it without a second lookup.
fn selectName(st: *State) void {
    if (st.sel >= st.count) return;
    const e = st.entries[st.sel];
    const n = @min(e.len, max_name);
    @memset(&st.name, ' ');
    @memcpy(st.name[0..n], e.name[0..n]);
}

/// setsele refuses an empty list (menu.inc: `lda filecnt; beq setfnam`).
fn cycleWindow(st: *State) void {
    switch (st.window) {
        .name_typer => st.window = if (st.editauth) .author_typer else .selector,
        .author_typer => st.window = .selector,
        .selector => st.window = .name_typer,
    }
    if (st.window == .selector and st.count == 0) st.window = .name_typer;
    if (st.window == .author_typer) st.author_pos = 0 else st.name_pos = 0;
    if (st.window == .selector) selectName(st);
}

/// regname: trim the typed name's trailing spaces and append the extension.
fn regName(st: *const State) Name {
    var out = Name{};
    var last: i32 = -1;
    for (0..max_name) |i| if (st.name[i] != ' ') {
        last = @intCast(i);
    };
    const n: usize = @intCast(last + 1);
    @memcpy(out.buf[0..n], st.name[0..n]);
    const e = ext(st.kind);
    @memcpy(out.buf[n..][0..ext_len], &e);
    out.len = @intCast(n + ext_len);
    return out;
}

/// The active typing field (window 0 uses the name, window 1 the author).
fn field(st: *State) struct { buf: []u8, pos: *u8, max: u8 } {
    if (st.window == .author_typer) {
        return .{ .buf = &st.author, .pos = &st.author_pos, .max = author_len - 1 };
    }
    return .{ .buf = &st.name, .pos = &st.name_pos, .max = max_name - 1 };
}

fn insertChar(f: anytype) void {
    var i: usize = f.max;
    while (i > f.pos.*) : (i -= 1) f.buf[i] = f.buf[i - 1];
    f.buf[f.pos.*] = ' ';
}

fn backspaceChar(f: anytype) void {
    if (f.pos.* > 0) f.pos.* -= 1;
    var i: usize = f.pos.*;
    while (i < f.max) : (i += 1) f.buf[i] = f.buf[i + 1];
    f.buf[f.max] = ' ';
}

fn stepSelection(st: *State, delta: i32) void {
    if (st.count == 0) return;
    const last: i32 = @as(i32, st.count) - 1;
    var v: i32 = @as(i32, st.sel) + delta;
    if (v < 0) v = 0;
    if (v > last) v = last;
    st.sel = @intCast(v);
    st.col = @intCast(@mod(v, columns));
    selectName(st);
}

fn typeKey(st: *State, k: Key) Action {
    const f = field(st);
    switch (k) {
        .home => f.pos.* = 0,
        .insert => insertChar(f),
        .backspace => backspaceChar(f),
        .right => if (f.pos.* < f.max) {
            f.pos.* += 1;
        },
        .char => |ch| {
            if (ch < 0x80) {
                f.buf[f.pos.*] = ch;
                if (f.pos.* < f.max) f.pos.* += 1;
            }
        },
        // $fb/$fe (cursor down / STOP) leave the field untouched
        .none, .down, .tab, .ret, .stop, .dir, .page => return .none,
    }
    return .redraw;
}

/// filenamer/filkeys: one key inside the dialog.
pub fn key(st: *State, k: Key, shift: bool) Action {
    if (!st.open) return .none;
    switch (k) {
        .tab => {
            cycleWindow(st);
            return .redraw;
        },
        .stop => {
            st.open = false;
            return .close;
        },
        .dir => {
            st.more = true;
            return .need_listing;
        },
        .page => return if (st.more) .need_listing else .none,
        .ret => {
            if (st.window == .author_typer) { // lopove1: back to the name typer
                st.window = .name_typer;
                st.name_pos = 0;
                return .redraw;
            }
            const name = regName(st);
            if (name.len == ext_len) return .none; // empty filename
            st.open = false;
            return if (st.mode == .load) .{ .load = name } else .{ .save = name };
        },
        else => {},
    }
    if (st.window == .selector) {
        // fiselLR: cursor-down steps 3 places, cursor-right 1; shift reverses
        switch (k) {
            .down => stepSelection(st, if (shift) -3 else 3),
            .right => stepSelection(st, if (shift) -1 else 1),
            else => return .none,
        }
        return .redraw;
    }
    if (k == .right) {
        const f = field(st);
        if (shift) {
            if (f.pos.* > 0) f.pos.* -= 1; // fcurbwd
        } else if (f.pos.* < f.max) {
            f.pos.* += 1; // fcurfwd
        }
        return .redraw;
    }
    return typeKey(st, k);
}
