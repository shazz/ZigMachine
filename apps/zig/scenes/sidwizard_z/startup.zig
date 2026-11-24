//! startup.zig — the start-up menu (Part 4, asm/include/startupmenu.inc).
//! The original opens with a fader/skew/raster effect and lets the user pick
//! one of the alternative players, the tuning table, and confirms the config
//! file load before the editor starts. The player choice is meaningless in the
//! native port (the 6502 player is fixed), but the state machine and its text
//! screen are kept so the host can show the same menu and apply the tuning /
//! config result.
//!
//! Not ported: the raster fader, the $d016 skew trick, the player-code copying
//! (altplayers.inc), and the feature-tick grid (see NOTES.md "Known gaps").
const std = @import("std");
const dsp = @import("display.zig");

pub const player_count = 6; // NumberOfPlayerTypes

/// PlrList order: normal, medium, light, extra, bare, demo.
pub const player_names = [player_count][]const u8{
    "NORMAL", "MEDIUM", "LIGHT!", "EXTRA!", "(BARE)", "DEMO",
};

/// The two 39-character description lines each player scrolls across rows
/// 19/20 (altplayers.inc `description`).
const descriptions = [player_count][2][]const u8{
    .{ "The default player which features all   ", "the necessities and almost every extra. " },
    .{ "A moderately reduced player, It has got ", "almost all function but less rastertime." },
    .{ "A reduced player with small rastertime, ", "all extra features are switched off...  " },
    .{ "All extra features are switched on, and ", "no matter what rastertime it takes...   " },
    .{ "Very reduced: No subtunes, orderlist-FX,", "no multispeed,arptable-nop,some smallfx." },
    .{ "Includes features needed for demo-music,", "lacks subtune,filtershift,some smallefx." },
};

/// altplayers.inc rastimes/plysizes for SID_AMOUNT=1.
const raster_times = [player_count][]const u8{ "$1C ", "$1B ", "$17 ", "$23 ", "$17 ", "$19 " };
const player_sizes = [player_count][]const u8{ "$A57", "$99A", "$7FA", "$AEF", "$71A", "$89B" };

/// Config.TuningType: 0 equal, 1 Verdi, 2 just, 3 Drean.
pub const tuning_texts = [4][]const u8{
    ": Equal-tempered, A5=440Hz ",
    ": Verdi-tuning ,  A5=432Hz ",
    ":Just-inton.keyC,A=436.05Hz",
    ":Drean(PALtiming,NTSCpitch)",
};

pub const Machine = enum { pal, ntsc, drean };

pub const State = struct {
    open: bool = true,
    selection: u8 = 0, // Config.PlayerType
    tuning: u8 = 0, // Config.TuningType
    cfg_found: bool = false, // menu.cfgstat != '?'
    machine: Machine = .pal,
    scrollcnt: u8 = 0, // playertxt's 0..40 scroller
};

pub const Action = enum {
    none,
    redraw,
    start, // RETURN/SPACE: leave the menu, the editor boots
};

/// init: the values the BASIC starter/config loader would have set.
pub fn init(cfg_found: bool, machine: Machine, tuning: u8, player: u8) State {
    return .{
        .cfg_found = cfg_found,
        .machine = machine,
        .tuning = tuning % 4,
        .selection = player % player_count,
    };
}

/// KeyBdCh: CRSR↓ (shift = up) cycles the player, CRSR→ cycles the tuning,
/// RETURN/SPACE starts the editor.
pub fn key(st: *State, code: u6, shift: bool) Action {
    if (!st.open) return .none;
    switch (code) {
        7 => { // chCurDn
            if (shift) {
                st.selection = if (st.selection == 0) player_count - 1 else st.selection - 1;
            } else {
                st.selection = if (st.selection + 1 >= player_count) 0 else st.selection + 1;
            }
            st.scrollcnt = 0; // newmnpt
            return .redraw;
        },
        2 => { // chCurRi
            st.tuning = (st.tuning + 1) % 4;
            return .redraw;
        },
        1, 60 => { // RETURN or SPACE (chRetur/chSpace)
            st.open = false;
            return .start;
        },
        else => return .none,
    }
}

/// playertxt: one frame of the description scroll (0..40 then stop).
pub fn tick(st: *State) void {
    if (st.scrollcnt < 40) st.scrollcnt += 1;
}

/// 64tass `.enc "screen"` (startupmenu.inc strings): upper-case letters stay
/// ASCII (the small ROM set shows $41..$5a as capitals), lower-case a-z become
/// screen codes 1..26.
pub fn screenCode(ch: u8) u8 {
    return if (ch >= 'a' and ch <= 'z') ch - 0x60 else ch;
}

fn textAt(scr: *dsp.Screen, r: usize, c: usize, text: []const u8, col: u4) void {
    for (text, 0..) |ch, i| {
        if (c + i >= dsp.COLS) break;
        scr.chars[r][c + i] = screenCode(ch);
        scr.colours[r][c + i] = col;
    }
}

fn scrollLine(st: *const State, line: []const u8, scr: *dsp.Screen, row: usize) void {
    const off: usize = @min(st.scrollcnt, line.len);
    textAt(scr, row, 0, line[off..], 11);
}

/// dismenu/DispFeat/playertxt on the text screen: title, config result,
/// the player list with its raster/size numbers, the scrolled description,
/// the machine and the tuning line.
pub fn render(st: *const State, scr: *dsp.Screen) void {
    for (0..dsp.ROWS) |r| {
        for (0..dsp.COLS) |c| {
            scr.chars[r][c] = ' ';
            scr.colours[r][c] = 12; // decorcol
        }
    }
    textAt(scr, 1, 0, "      SID-WIZARD 1.X  STARTUP-MENU      ", 13);
    const cfg = if (st.cfg_found)
        "Configuration file loaded successfully.."
    else
        "Configuration file was not (yet) found! ";
    textAt(scr, 3, 0, cfg, 13);
    textAt(scr, 5, 0, "  Please select your preferred player:  ", 13);
    for (0..player_count) |i| {
        const col: u4 = if (i == st.selection) 15 else 11;
        textAt(scr, 6 + i * 2, 16, player_names[i], col);
        textAt(scr, 6 + i * 2, 26, raster_times[i], col);
        textAt(scr, 6 + i * 2, 31, player_sizes[i], col);
    }
    const d = descriptions[st.selection];
    scrollLine(st, d[0], scr, 18);
    scrollLine(st, d[1], scr, 19);
    textAt(scr, 21, 3, "RasterTime:", 11);
    textAt(scr, 21, 15, raster_times[st.selection], 11);
    textAt(scr, 21, 21, "Player-Size:", 11);
    textAt(scr, 21, 33, player_sizes[st.selection], 11);
    const mach = switch (st.machine) {
        .pal => " PAL  machine detected,pitches adjusted.",
        .ntsc => "NTSC machine detected,pitches adjusted. ",
        .drean => "Drean machine detected,pitches adjusted.",
    };
    textAt(scr, 23, 0, mach, 11);
    textAt(scr, 24, 13, tuning_texts[st.tuning], 11);
}
