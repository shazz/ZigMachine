// --------------------------------------------------------------------------
// BUBBLE BOBBLE — the cart. A port of olivierh59500's Go/Ebitengine remake
// (internal/app + internal/game) onto the ZigMachine:
//
//   * the world is sim.zig (fixed point, 60 Hz, the Go's own 32x26 tiles),
//   * the picture is art.zig on ONE 400x280 overscan plane, the Go's
//     768x720 canvas mapped by /3 so the playfield is exactly 256x208,
//   * the sound is audio.zig: the five original YM tunes replayed through the
//     machine's YM2149 and the ten WAV effects through the cart audio ring,
//   * the pages are the Go's own (title, menu, profiles, high scores, settings,
//     help, credits, level editor, play, result) with a keyboard UI.
//
// Everything the Go stores in its save file is RAM-only here (ZigOS has no
// writable disk), which is exactly what a cartridge would have had.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const sim = @import("bubblebobble/sim.zig");
const art = @import("bubblebobble/art.zig");
const audio = @import("bubblebobble/audio.zig");
const assets = @import("bubblebobble/assets.zig");

// --- keys -------------------------------------------------------------------
const K_ENTER: u32 = 13;
const K_SPACE: u32 = 32;
const K_ESC: u32 = 0xE012;
const K_TAB: u32 = 9;
const K_UP: u32 = 0xE020;
const K_DOWN: u32 = 0xE021;
const K_LEFT: u32 = 0xE022;
const K_RIGHT: u32 = 0xE023;

var kLeft = false;
var kRight = false;
var kUp = false;
var kDown = false;
var kJump = false; // up / W
var kFire = false; // space / control
var kConfirm = false; // enter (edge)
var kBack = false; // escape (edge)
var kTab = false; // edge
var kBackspace = false; // edge
var kMute = false; // edge (M)
var kDelete = false; // edge (the editor's erase modifier)
var kJumpW = false; // W held
var kShift = false;

fn isUpKey(cp: u32) bool {
    return cp == K_UP or cp == 'w';
}
fn isLeftKey(cp: u32) bool {
    return cp == K_LEFT or cp == 'a' or cp == 'A';
}
fn isRightKey(cp: u32) bool {
    return cp == K_RIGHT or cp == 'd' or cp == 'D';
}

// --- the world --------------------------------------------------------------
pub var game: sim.Game = .{};
var seed: u64 = 0x1234_5678;
var tickAccum: f32 = 0;
var audioAccum: f32 = 0;
pub var frame: i32 = 0;

// --- the player's saved profile (RAM only) ----------------------------------
const Profile = struct {
    name: [16]u8 = [_]u8{' '} ** 16,
    name_len: u8 = 0,
    avatar: u8 = 0, // 0 green, 1 blue
    high_score: i32 = 0,
    best_round: i32 = 1,
    played: i32 = 0,
    won: i32 = 0,
    lost: i32 = 0,
    xp: i32 = 0,

    fn setName(self: *Profile, s: []const u8) void {
        const n = @min(s.len, self.name.len);
        @memcpy(self.name[0..n], s[0..n]);
        self.name_len = @intCast(n);
    }
    fn nameSlice(self: *const Profile) []const u8 {
        return self.name[0..self.name_len];
    }
};

var profiles: [4]Profile = .{ .{}, .{}, .{}, .{} };
var profile_count: u8 = 1;
var active: u8 = 0;
var music_vol: i32 = 50;
var sound_vol: i32 = 75;

fn profile() *Profile {
    return &profiles[active];
}

var name_typing: [16]u8 = [_]u8{' '} ** 16;
var name_typing_len: u8 = 0;

// --- pages ------------------------------------------------------------------
const Page = enum { title, menu, profiles, new_profile, scores, settings, help, credits, editor, play, result };
var page: Page = .title;
var selected: u8 = 0;
var last_track: i32 = -1;

// --- the editor -------------------------------------------------------------
const Editor = struct {
    level: sim.Level = .{},
    tool: u8 = 0,
    template: u8 = 0,
    cursor: sim.Cell = .{ .col = 4, .row = 10 },
    history: [6]sim.Level = [_]sim.Level{.{}} ** 6,
    history_n: u8 = 0,
    saved: sim.Level = .{},
    has_saved: bool = false,
};

const TOOLS = [_][]const u8{ "BLOCK", "ERASER", "PLAYER", "FOOD", "BONUS", "ZENCHAN", "MONSTA", "MIGHTA", "PULPUL", "BANEBOU", "INVADER" };
const TOOL_COUNT: u8 = 11;

var editor: Editor = .{};

const editorX: i32 = 20;
const editorY: i32 = 40;
const editorTile: i32 = 8;

fn editorRemember() void {
    if (editor.history_n < editor.history.len) {
        editor.history[editor.history_n] = editor.level;
        editor.history_n += 1;
    } else {
        var i: u8 = 1;
        while (i < editor.history.len) : (i += 1) editor.history[i - 1] = editor.history[i];
        editor.history[editor.history.len - 1] = editor.level;
    }
}

fn editorUndo() void {
    if (editor.history_n == 0) return;
    editor.history_n -= 1;
    editor.level = editor.history[editor.history_n];
}

// --------------------------------------------------------------------------
pub const Demo = struct {
    pub fn init(self: *Demo, zigos: *ZigOS) void {
        _ = self;
        art.setup(zigos);
        audio.init();
        initProfile();
        editor.level = sim.loadLevelData(0);
        game.reset(seed, 1);
        game.paused = true;
        page = .title;
        last_track = -1;
        art.clear();
    }

    fn initProfile() void {
        profiles[0] = .{};
        profiles[0].setName("PLAYER1");
        profiles[0].avatar = 0;
        profile_count = 1;
        active = 0;
    }

    pub fn update(self: *Demo, _: *ZigOS, dt_ms: f32) void {
        _ = self;
        audio.update(dt_ms);
        frame += 1;
        if (std.math.isFinite(dt_ms) and dt_ms > 0) {
            tickAccum += @min(dt_ms, 200.0);
            audioAccum += @min(dt_ms, 200.0);
        }
        // The world runs at the Go's own 60 Hz whatever the display does.
        while (tickAccum >= 1000.0 / 60.0) {
            tickAccum -= 1000.0 / 60.0;
            tick();
        }
        // The YM is a 50 Hz machine.
        while (audioAccum >= 20.0) {
            audioAccum -= 20.0;
            audio.tick();
        }
        kConfirm = false;
        kBack = false;
        kTab = false;
        kBackspace = false;
        kMute = false;
        kDelete = false;
    }

    fn tick() void {
        if (page == .play) {
            if (kBack) {
                game.paused = !game.paused;
                selected = 0;
            }
            if (game.paused) {
                menusNav();
            } else {
                var in = sim.Input{};
                in.move = (if (kRight) @as(i32, 1) else 0) - (if (kLeft) @as(i32, 1) else 0);
                in.jump = kJump;
                in.fire = kFire;
                game.step(in);
                drainSounds();
                if (game.state == .game_over or game.state == .won) {
                    record(game.state == .won);
                    page = .result;
                    selected = 0;
                }
            }
        } else if (page == .editor) {
            editorTick();
        } else if (page != .title) {
            menusNav();
        } else {
            if (kConfirm or kFire) {
                page = .menu;
                selected = 0;
            }
        }
        if (kMute) {
            audio.toggleMute();
        }
        updateMusic();
    }

    fn drainSounds() void {
        for (game.sounds[0..game.sound_count]) |s| audio.sfx(@intFromEnum(s));
        game.sound_count = 0;
    }

    fn record(won: bool) void {
        const p = profile();
        p.played += 1;
        if (won) p.won += 1 else p.lost += 1;
        p.xp += game.score;
        if (game.score > p.high_score) p.high_score = game.score;
        if (game.level.number > p.best_round) p.best_round = game.level.number;
        if (p.best_round > 25) p.best_round = 25;
    }

    fn updateMusic() void {
        var want: i32 = @intFromEnum(audio.Track.menu);
        if (page == .play or page == .result) {
            want = @intFromEnum(audio.Track.theme);
            if (game.state == .won) {
                want = @intFromEnum(audio.Track.win);
            } else if (game.state == .game_over) {
                want = @intFromEnum(audio.Track.gameover);
            } else if (game.hurry) {
                want = @intFromEnum(audio.Track.hurry);
            }
        }
        if (want != last_track) {
            last_track = want;
            audio.play(@enumFromInt(want));
        }
    }

    // --- the pages' lists ---------------------------------------------------
    fn itemCount() u8 {
        return switch (page) {
            .menu => 8,
            .profiles => profile_count + 2,
            .new_profile => 40,
            .settings => 4,
            .scores, .help, .credits => 1,
            .result => 2,
            .play => if (game.paused) 3 else 0,
            else => 0,
        };
    }

    fn itemLabel(i: u8, buf: []u8) []const u8 {
        switch (page) {
            .menu => return switch (i) {
                0 => "START GAME",
                1 => "PROFILES",
                2 => "HIGH SCORES",
                3 => "LEVEL EDITOR",
                4 => "SETTINGS",
                5 => "HOW TO PLAY",
                6 => "CREDITS",
                else => "QUIT",
            },
            .profiles => {
                if (i < profile_count) return profiles[i].nameSlice();
                if (i == profile_count) return "NEW PROFILE";
                return "BACK";
            },
            .new_profile => {
                if (i < 36) {
                    const ch = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[i];
                    buf[0] = ch;
                    return buf[0..1];
                }
                if (i == 36) return "SPACE";
                if (i == 37) return "DEL";
                if (i == 38) return "CREATE PROFILE";
                return "CANCEL";
            },
            .settings => return switch (i) {
                0 => if (profile().avatar == 0) "DRAGON: GREEN" else "DRAGON: BLUE",
                1 => std.fmt.bufPrint(buf, "MUSIC: {d}%", .{music_vol}) catch "MUSIC",
                2 => std.fmt.bufPrint(buf, "SOUND: {d}%", .{sound_vol}) catch "SOUND",
                else => "BACK",
            },
            .scores, .help, .credits => return "BACK",
            .result => return if (i == 0) "PLAY AGAIN" else if (game.custom) "BACK TO EDITOR" else "MAIN MENU",
            .play => return switch (i) {
                0 => "RESUME",
                1 => "RESTART",
                else => if (game.custom) "BACK TO EDITOR" else "END RUN",
            },
            else => return "",
        }
    }

    fn itemAction(i: u8) void {
        switch (page) {
            .menu => switch (i) {
                0 => startGame(false),
                1 => go(.profiles),
                2 => go(.scores),
                3 => {
                    editor.level = sim.loadLevelData(editor.template);
                    editor.history_n = 0;
                    go(.editor);
                },
                4 => go(.settings),
                5 => go(.help),
                6 => go(.credits),
                else => quitCart = true,
            },
            .profiles => {
                if (i < profile_count) {
                    active = i;
                    selected = i;
                } else if (i == profile_count) {
                    name_typing_len = 0;
                    @memset(&name_typing, ' ');
                    go(.new_profile);
                } else go(.menu);
            },
            .new_profile => {
                if (i < 36) {
                    typeChar("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[i]);
                } else if (i == 36) {
                    typeChar(' ');
                } else if (i == 37) {
                    if (name_typing_len > 0) name_typing_len -= 1;
                } else if (i == 38) {
                    if (profile_count < profiles.len) {
                        profiles[profile_count] = .{};
                        profiles[profile_count].setName(name_typing[0..name_typing_len]);
                        profiles[profile_count].avatar = @intCast(profile_count % 2);
                        active = profile_count;
                        profile_count += 1;
                    }
                    go(.profiles);
                } else go(.profiles);
            },
            .settings => switch (i) {
                0 => profile().avatar = 1 - profile().avatar,
                1 => music_vol = @mod(music_vol + 25, 125),
                2 => sound_vol = @mod(sound_vol + 25, 125),
                else => go(.menu),
            },
            .scores, .help, .credits => go(.menu),
            .result => {
                if (i == 0) startGame(false) else go(.menu);
            },
            .play => switch (i) {
                0 => game.paused = false,
                1 => startGame(game.custom),
                else => go(.menu),
            },
            else => {},
        }
    }

    fn typeChar(c: u8) void {
        if (name_typing_len < name_typing.len) {
            name_typing[name_typing_len] = c;
            name_typing_len += 1;
        }
    }

    fn go(p: Page) void {
        page = p;
        selected = 0;
    }

    fn startGame(custom: bool) void {
        seed = seed *% 6364136223846793005 +% 1442695040888963407;
        game.reset(seed, 1);
        if (!custom) {
            game.loadLevel(0);
        } else {
            game.startCustom(editor.level);
        }
        game.paused = false;
        page = .play;
        selected = 0;
    }

    /// Up/down/confirm over the current page's item list.
    fn menusNav() void {
        const n = itemCount();
        if (n == 0) return;
        var sel = selected;
        if (kUp or kTab) {
            sel = if (sel == 0) n - 1 else sel - 1;
        }
        if (kDown) {
            sel = (sel + 1) % n;
        }
        selected = @min(sel, n - 1);
        if (kConfirm or kFire) {
            itemAction(selected);
        } else if (kBack) {
            if (page == .menu) {
                go(.title);
            } else if (page == .profiles or page == .scores or page == .settings or page == .help or page == .credits or page == .new_profile) {
                go(.menu);
            } else if (page == .result) {
                go(.menu);
            }
        }
    }

    // --- the editor ---------------------------------------------------------
    fn editorTick() void {
        if (kBack) {
            go(.menu);
            return;
        }
        if (kConfirm or kFire) {
            editorPaint(true);
        }
        if (kDelete) {
            editorPaint(false);
        }
        // The cursor, then the tools, then the panel buttons.
        const cursor_max = 5 + TOOL_COUNT + 6;
        var sel = selected;
        if (kUp) sel = if (sel == 0) cursor_max - 1 else sel - 1;
        if (kDown) sel = (sel + 1) % cursor_max;
        if (kLeft or kRight) {
            if (sel == 0) {
                editor.cursor.col += if (kRight) @as(i32, 1) else -1;
                if (editor.cursor.col < 2) editor.cursor.col = 2;
                if (editor.cursor.col > 29) editor.cursor.col = 29;
            } else if (sel == 3) {
                editor.template = @intCast(@mod(@as(i32, editor.template) + (if (kRight) @as(i32, 1) else -1) + 25, 25));
            } else if (sel == 1 or sel == 2) {
                editor.tool = @intCast(@mod(@as(i32, editor.tool) + (if (kRight) @as(i32, 1) else -1) + TOOL_COUNT, TOOL_COUNT));
            }
        }
        if (sel == 0 and kJumpW) {
            editor.cursor.row += 1;
            if (editor.cursor.row > 24) editor.cursor.row = 24;
        }
        selected = sel;
        editorButtons();
    }

    fn editorPaint(draw: bool) void {
        editorRemember();
        const c = editor.cursor;
        if (!draw) {
            editor.level.tiles[@intCast(c.row)][@intCast(c.col)] = 0;
            return;
        }
        switch (editor.tool) {
            0 => editor.level.tiles[@intCast(c.row)][@intCast(c.col)] = tileFor(c),
            2 => {
                editor.level.player = c;
                clampCell(&editor.level.player);
            },
            3 => {
                editor.level.food = c;
                clampCell(&editor.level.food);
            },
            4 => {
                editor.level.power = c;
                clampCell(&editor.level.power);
            },
            5, 6, 7, 8, 9, 10 => {
                if (editor.level.enemy_count < editor.level.enemies.len) {
                    var used = false;
                    for (editor.level.enemies[0..editor.level.enemy_count]) |e| {
                        if (e.col == c.col and e.row == c.row) used = true;
                    }
                    if (!used) {
                        editor.level.enemies[editor.level.enemy_count] = .{ .kind = @enumFromInt(editor.tool - 5), .col = @intCast(c.col), .row = @intCast(c.row) };
                        editor.level.enemy_count += 1;
                    }
                }
            },
            else => editor.level.tiles[@intCast(c.row)][@intCast(c.col)] = 0,
        }
    }

    fn tileFor(c: sim.Cell) u8 {
        // A block that looks like the campaign's own brick for this row, so a
        // hand-drawn level still reads as Bubble Bobble.
        _ = c;
        return 1;
    }

    fn clampCell(cell: *sim.Cell) void {
        if (cell.col < 2) cell.col = 2;
        if (cell.col > 29) cell.col = 29;
        if (cell.row < 1) cell.row = 1;
        if (cell.row > 24) cell.row = 24;
    }

    fn editorButtons() void {
        if (selected == 0) return;
        const idx = selected;
        // 1..2: tool step; 3: template; 4: undo; 5: menu; 6..: tools / actions
        switch (idx) {
            1 => editor.tool = @intCast(@mod(@as(i32, editor.tool) + TOOL_COUNT - 1, TOOL_COUNT)),
            2 => editor.tool = @intCast(@mod(@as(i32, editor.tool) + 1, TOOL_COUNT)),
            3 => editor.level = sim.loadLevelData(editor.template),
            4 => editorUndo(),
            5 => go(.menu),
            else => {
                const t = idx - 6;
                if (t < TOOL_COUNT) {
                    editor.tool = t;
                } else switch (t - TOOL_COUNT) {
                    0 => editorRemember(), // new
                    1 => editor.saved = editor.level,
                    2 => {
                        if (editor.has_saved) editor.level = editor.saved;
                    },
                    3 => {
                        editor.level.special = @enumFromInt((@intFromEnum(editor.level.special) + 1) % 4);
                    },
                    4 => editor.level.number = @intCast(@mod(@as(i32, editor.level.number), 25) + 1),
                    5 => startGame(true),
                    else => {},
                }
            },
        }
        if (idx >= 1) selected = 0;
    }

    // --- keys ---------------------------------------------------------------
    pub fn ownsKeyboard(self: *Demo) u32 {
        _ = self;
        return 1; // a game owns every key; the pad arrives through input()
    }

    pub fn key(self: *Demo, cp: u32) void {
        _ = self;
        if (page == .new_profile) {
            if (cp >= 'a' and cp <= 'z') {
                typeChar(@intCast(cp - 32));
                return;
            }
            if ((cp >= '0' and cp <= '9') or (cp >= 'A' and cp <= 'Z')) {
                typeChar(@intCast(cp));
                return;
            }
            if (cp == K_SPACE) {
                typeChar(' ');
                return;
            }
        }
        noteKeyDown(cp);
    }

    pub fn input(_: *Demo, dir: u8) void {
        switch (dir) {
            0 => {
                kUp = true;
                kJump = true;
            },
            1 => kDown = true,
            2 => kLeft = true,
            3 => kRight = true,
            5 => kFire = true,
            else => {},
        }
    }

    pub fn inputRelease(_: *Demo, dir: u8) void {
        switch (dir) {
            0 => {
                kUp = false;
                kJump = false;
            },
            1 => kDown = false,
            2 => kLeft = false,
            3 => kRight = false,
            5 => kFire = false,
            else => {},
        }
    }

    pub fn pollCart(self: *Demo) i32 {        _ = self;
        if (quitCart) {
            quitCart = false;
            return -1;
        }
        return 0;
    }

    // --- render -------------------------------------------------------------
    pub fn render(self: *Demo, _: *ZigOS, _: f32) void {
        _ = self;
        switch (page) {
            .title => drawTitle(),
            .menu => drawMenu(),
            .profiles => drawProfiles(),
            .new_profile => drawNewProfile(),
            .scores => drawScores(),
            .settings => drawSettings(),
            .help => drawHelp(),
            .credits => drawCredits(),
            .editor => drawEditor(),
            .play => {
                drawMatch();
                if (game.paused) drawPause();
            },
            .result => {
                drawMatch();
                drawResult();
            },
        }
    }
};

var quitCart = false;

// --------------------------------------------------------------------------
// Editing the cart's key state.
// --------------------------------------------------------------------------
pub fn noteKeyDown(cp: u32) void {
    if (isLeftKey(cp)) kLeft = true;
    if (isRightKey(cp)) kRight = true;
    if (isUpKey(cp)) {
        kJump = true;
        kUp = true;
    }
    if (cp == K_DOWN or cp == 's' or cp == 'S') kDown = true;
    if (cp == K_UP) kUp = true;
    if (cp == K_SPACE or cp == 17 or cp == 'z' or cp == 'Z') kFire = true;
    if (cp == K_ENTER) kConfirm = true;
    if (cp == K_ESC) kBack = true;
    if (cp == K_TAB) kTab = true;
    if (cp == 8 or cp == 127) kBackspace = true;
    if (cp == 'm' or cp == 'M') kMute = true;
    if (cp == 'x' or cp == 'X') kDelete = true;
    if (cp == 'w' or cp == 'W') kJumpW = true;
}

pub fn noteKeyUp(cp: u32) void {
    if (isLeftKey(cp)) kLeft = false;
    if (isRightKey(cp)) kRight = false;
    if (isUpKey(cp)) {
        kJump = false;
        kUp = false;
    }
    if (cp == K_DOWN or cp == 's' or cp == 'S') kDown = false;
    if (cp == K_SPACE or cp == 17 or cp == 'z' or cp == 'Z') kFire = false;
    if (cp == 'w' or cp == 'W') kJumpW = false;
}

// --------------------------------------------------------------------------
// Screens.
// --------------------------------------------------------------------------
fn buf7(v: i32) []const u8 {
    const s = std.fmt.bufPrint(&num_buf, "{d:0>7}", .{@max(0, v)}) catch "0000000";
    return s;
}
var num_buf: [16]u8 = undefined;
var num_buf2: [24]u8 = undefined;
var num_buf3: [24]u8 = undefined;

fn menuLogo() void {
    art.logo(132, 16);
}

/// The Go's menu list, drawn centred under the logo.
fn drawList(y0: i32, spacing: i32) void {
    const n = Demo.itemCount();
    var buf: [24]u8 = undefined;
    var i: u8 = 0;
    while (i < n) : (i += 1) {
        const label = Demo.itemLabel(i, &buf);
        const y = y0 + @as(i32, i) * spacing;
        const w = art.textWidth(label);
        if (i == selected) {
            art.box(196 - @divTrunc(w, 2) - 6, y - 3, w + 12, 14, assets.GREEN);
            art.text(label, 196 - @divTrunc(w, 2), y, assets.INK, assets.GREEN);
        } else {
            art.text(label, 196 - @divTrunc(w, 2), y, assets.WHITE, assets.INK);
        }
    }
}

fn drawTitle() void {
    art.clear();
    menuLogo();
    const p = profile();
    var buf: [40]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, "{s}  /  BEST {d:0>7}", .{ p.nameSlice(), p.high_score }) catch "";
    art.center(line, 112, assets.GREEN, assets.INK);
    art.spr(art.PLAYER[0][0], frame, 60, 150, 32, 1);
    art.spr(art.PLAYER[1][0], frame, 308, 150, 32, -1);
    art.center("25 ROUNDS. ONE BUBBLY ADVENTURE.", 150, assets.WHITE, assets.INK);
    if (@mod(@divTrunc(frame, 10), 6) < 4) {
        art.center("PRESS ENTER TO START", 180, assets.YELLOW, assets.INK);
    }
    art.center("ARROWS TO SELECT   ENTER TO CONFIRM   M MUTE", 258, assets.MUTED, assets.INK);
}

fn drawMenu() void {
    art.clear();
    menuLogo();
    const p = profile();
    var buf: [40]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, "{s}  /  BEST {d:0>7}", .{ p.nameSlice(), p.high_score }) catch "";
    art.center(line, 108, assets.GREEN, assets.INK);
    drawList(132, 18);
    art.center("ARROWS TO SELECT   ENTER TO CONFIRM   M MUTE", 258, assets.MUTED, assets.INK);
}

fn drawProfiles() void {
    art.clear();
    art.heading("PLAYER PROFILES", "SELECT A PLAYER OR CREATE A NEW PROFILE");
    drawList(80, 20);
    art.center("PROGRESS IS KEPT FOR THIS SESSION", 258, assets.MUTED, assets.INK);
}

fn drawNewProfile() void {
    art.clear();
    art.heading("NEW PLAYER", "PICK LETTERS, SPACE OR DEL");
    art.box(96, 60, 208, 20, assets.PANEL);
    art.center(name_typing[0..name_typing_len], 66, assets.GREEN, assets.PANEL);
    drawList(96, 18);
}

fn drawScores() void {
    art.clear();
    art.heading("HIGH SCORES", "LOCAL PLAYERS / ALL CAMPAIGN RUNS");
    art.small("PLAYER", 24, 62, assets.MUTED, assets.INK);
    art.small("SCORE", 180, 62, assets.MUTED, assets.INK);
    art.small("ROUND", 280, 62, assets.MUTED, assets.INK);
    art.small("W / L", 344, 62, assets.MUTED, assets.INK);
    var i: u8 = 0;
    while (i < profile_count) : (i += 1) {
        const p = &profiles[i];
        const y: i32 = 78 + @as(i32, i) * 22;
        art.box(16, y - 3, 368, 18, assets.PANEL);
        art.text(p.nameSlice(), 24, y, assets.WHITE, assets.PANEL);
        const sc = std.fmt.bufPrint(&num_buf2, "{d:0>7}", .{p.high_score}) catch "";
        art.text(sc, 180, y, assets.YELLOW, assets.PANEL);
        const rd = std.fmt.bufPrint(&num_buf3, "{d:0>2}", .{p.best_round}) catch "";
        art.text(rd, 280, y, assets.GREEN, assets.PANEL);
        const wl = std.fmt.bufPrint(&num_buf3, "{d}/{d}", .{ p.won, p.lost }) catch "";
        art.text(wl, 344, y, assets.WHITE, assets.PANEL);
    }
    drawList(220, 18);
}

fn drawSettings() void {
    art.clear();
    art.heading("SETTINGS", "ENTER TO CHANGE");
    const p = profile();
    art.spr(art.PLAYER[p.avatar][0], frame, 176, 76, 48, -1);
    var buf: [48]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, "{s}  /  PLAYER LEVEL {d}", .{ p.nameSlice(), @divTrunc(p.xp, 100) + 1 }) catch "";
    art.center(line, 136, assets.GREEN, assets.INK);
    const stats = std.fmt.bufPrint(&buf, "PLAYED {d}  WON {d}  LOST {d}  XP {d}", .{ p.played, p.won, p.lost, p.xp }) catch "";
    art.smallCenter(stats, 152, assets.MUTED, assets.INK);
    drawList(176, 20);
}

fn drawHelp() void {
    art.clear();
    art.heading("HOW TO PLAY", "TRAP THE ENEMIES. POP THE BUBBLES. COLLECT THE FRUIT.");
    const lines = [_][2][]const u8{
        .{ "MOVE", "LEFT / RIGHT OR A / D" },
        .{ "JUMP", "UP OR W - HOLD TO BOUNCE ON BUBBLES" },
        .{ "BLOW BUBBLES", "SPACE OR Z - TOUCH A BUBBLE TO POP IT" },
        .{ "TAKE A BREAK", "ESC TO PAUSE / M MUTE" },
        .{ "BONUSES", "CANDIES, SHOES, RINGS, PARASOLS, CLOCK, DYNAMITE" },
        .{ "ELEMENTS", "WATER FLOWS, LIGHTNING STRIKES, FIRE SPREADS" },
        .{ "SURVIVE", "3 LIVES / ENEMIES GET ANGRY AFTER 30 SECONDS" },
    };
    for (lines, 0..) |line, i| {
        const y: i32 = 62 + @as(i32, @intCast(i)) * 20;
        art.text(line[0], 24, y, assets.GREEN, assets.INK);
        art.small(line[1], 24, y + 9, assets.WHITE, assets.INK);
    }
    drawList(214, 18);
}

fn drawCredits() void {
    art.clear();
    art.heading("CREDITS", "A FAN REMAKE OF THE ARCADE CLASSIC");
    const lines = [_][]const u8{
        "ORIGINAL GAME AND CHARACTERS  TAITO",
        "GAME ADAPTATION AND LEVEL DESIGN",
        "MALAKH SOFTWARE - 2026",
        "GO EDITION POWERED BY EBITENGINE",
        "SOFTWARE LICENSE: MIT",
        "ARTWORK AND AUDIO BELONG TO THEIR OWNERS",
    };
    for (lines, 0..) |line, i| {
        const y: i32 = 60 + @as(i32, @intCast(i)) * 20;
        const c: u8 = if (i == 2) assets.GREEN else assets.WHITE;
        art.smallCenter(line, y, c, assets.INK);
    }
    drawList(196, 18);
}

fn drawResult() void {
    art.box(72, 36, 256, 208, assets.INK);
    const won = game.state == .won;
    art.center(if (won) "YOU WIN!" else "GAME OVER", 90, assets.GREEN, assets.INK);
    const sub: []const u8 = if (game.custom)
        "CUSTOM LEVEL PLAY TEST COMPLETE"
    else if (won)
        "ALL 25 ROUNDS CLEARED. WELL PLAYED!"
    else
        "A NEW ADVENTURE IS ONE BUBBLE AWAY.";
    art.smallCenter(sub, 112, assets.WHITE, assets.INK);
    var buf: [48]u8 = undefined;
    const sc = std.fmt.bufPrint(&buf, "SCORE  {d:0>7}", .{game.score}) catch "";
    art.center(sc, 130, assets.YELLOW, assets.INK);
    const p = profile();
    const best = std.fmt.bufPrint(&buf, "BEST {d:0>7}  /  LEVEL {d}", .{ p.high_score, p.best_round }) catch "";
    art.smallCenter(best, 148, assets.MUTED, assets.INK);
    drawList(176, 20);
}

fn drawPause() void {
    art.box(72, 36, 256, 208, assets.INK);
    art.center("PAUSED", 60, assets.GREEN, assets.INK);
    drawList(88, 20);
}

fn drawEditor() void {
    art.clear();
    art.heading("LEVEL EDITOR", "");
    // The grid: 32x26 tiles at 8 px, the playfield's own scale.
    art.box(editorX, editorY, 32 * editorTile, 26 * editorTile, assets.BLACK);
    var row: i32 = 0;
    while (row < 26) : (row += 1) {
        var col: i32 = 0;
        while (col < 32) : (col += 1) {
            const t = editor.level.tiles[@intCast(row)][@intCast(col)];
            if (t != 0) {
                art.tile(t, editorX + col * editorTile, editorY + row * editorTile);
            }
        }
    }
    // The cursor.
    art.box(editorX + editor.cursor.col * editorTile, editorY + editor.cursor.row * editorTile, editorTile, 1, assets.GREEN);
    art.box(editorX + editor.cursor.col * editorTile, editorY + editor.cursor.row * editorTile, 1, editorTile, assets.GREEN);
    // Spawns.
    var i: u8 = 0;
    while (i < editor.level.enemy_count) : (i += 1) {
        const e = editor.level.enemies[i];
        art.spr(art.WALK[@intFromEnum(e.kind)], frame, editorX + e.col * editorTile, editorY + e.row * editorTile, editorTile, -1);
    }
    art.spr(art.PLAYER[profile().avatar][0], frame, editorX + editor.level.player.col * editorTile, editorY + editor.level.player.row * editorTile, editorTile, -1);
    art.small("P", editorX + editor.level.player.col * editorTile, editorY + editor.level.player.row * editorTile - 7, assets.YELLOW, assets.INK);
    art.small("F", editorX + editor.level.food.col * editorTile, editorY + editor.level.food.row * editorTile - 7, assets.YELLOW, assets.INK);
    art.small("B", editorX + editor.level.power.col * editorTile, editorY + editor.level.power.row * editorTile - 7, assets.YELLOW, assets.INK);
    // The tool column.
    i = 0;
    while (i < TOOL_COUNT) : (i += 1) {
        const y: i32 = editorY + @as(i32, i) * 14;
        const sel = (i == editor.tool);
        if (sel) {
            art.box(288, y - 2, 108, 12, assets.GREEN);
            art.small(TOOLS[i], 292, y, assets.INK, assets.GREEN);
        } else {
            art.small(TOOLS[i], 292, y, assets.WHITE, assets.INK);
        }
    }
    var buf: [48]u8 = undefined;
    const tpl = std.fmt.bufPrint(&buf, "COPY ROUND {d:0>2}", .{@as(i32, editor.template) + 1}) catch "";
    art.small(tpl, 292, editorY + 11 * 14 + 10, assets.YELLOW, assets.INK);
    const cel = std.fmt.bufPrint(&buf, "BUBBLES {s}", .{@tagName(editor.level.special)}) catch "";
    art.small(cel, 292, editorY + 11 * 14 + 22, assets.WHITE, assets.INK);
    const tno = std.fmt.bufPrint(&buf, "TILE {d:0>2}  ENEMIES {d}", .{ editor.level.number, editor.level.enemy_count }) catch "";
    art.small(tno, 292, editorY + 11 * 14 + 34, assets.WHITE, assets.INK);
    art.small("SPACE PAINT  X ERASE  UP/DOWN TOOLS  LEFT/RIGHT MOVE", 16, 262, assets.MUTED, assets.INK);
    art.small("ENTER TEST PLAY  ESC RETURN", 16, 270, assets.GREEN, assets.INK);
}

// --------------------------------------------------------------------------
// The match: the Go's drawMatch, in the cart's own coordinates.
// --------------------------------------------------------------------------
fn enemyAnim(e: sim.Enemy) u8 {
    const k = @intFromEnum(e.kind);
    if (e.state == .defeated or e.state == .carried) return art.DEAD[k];
    if (e.kind == .mighta and e.shoot > 0) {
        return if (e.angry) art.MIGHTA_SHOOT_ANGRY else art.MIGHTA_SHOOT;
    }
    return if (e.angry) art.ANGRY[k] else art.WALK[k];
}

fn drawMatch() void {
    art.clear();
    // The playfield: black under the tiles, exactly the Go's box().
    art.box(art.PLAY_X, art.PLAY_Y, art.PLAY_W, art.PLAY_H, assets.BLACK);
    var row: i32 = 0;
    while (row < 26) : (row += 1) {
        var col: i32 = 0;
        while (col < 32) : (col += 1) {
            art.tile(game.level.tiles[@intCast(row)][@intCast(col)], art.PLAY_X + col * 8, art.PLAY_Y + row * 8);
        }
    }
    // Items.
    for (game.items[0..game.item_count]) |item| {
        if (item.age > 600 and @mod(item.age, 12) < 6) continue;
        const idx: u8 = if (item.power == .none) art.FOOD[@intCast(@min(item.food, 25) - 1)] else art.POWER[@intFromEnum(item.power)];
        art.spr(idx, 0, art.sx(item.body.x), art.sy(item.body.y), 11, -1);
    }
    // Enemies.
    for (game.enemies[0..game.enemy_count]) |e| {
        if (e.state == .trapped) continue;
        if (e.state == .defeated and e.dead_ticks == 0) continue;
        art.spr(enemyAnim(e), e.age, art.sx(e.body.x), art.sy(e.body.y), 16, e.dir);
    }
    // Bubbles.
    for (game.bubbles[0..game.bubble_count]) |b| {
        var idx: u8 = art.BUBBLE;
        var tick = @min(b.age, 30);
        if (b.element != .none) {
            idx = art.ELEMENT_BUBBLE[@intFromEnum(b.element)];
            tick = b.age;
        }
        if (b.age > 450 and b.enemy_id == 0 and b.element == .none) {
            idx = art.BUBBLE_WARNING;
            tick = b.age;
        }
        if (b.enemy_id != 0) {
            for (game.enemies[0..game.enemy_count]) |e| {
                if (e.id != b.enemy_id) continue;
                const k = @intFromEnum(e.kind);
                if (b.captured_age > 1200) {
                    idx = art.ESCAPE[k];
                } else if (b.captured_age > 1000) {
                    idx = art.WARNING[k];
                } else {
                    idx = art.BUBBLE_ANIM[k];
                }
                tick = b.age;
                break;
            }
        }
        art.spr(idx, tick, art.sx(b.body.x), art.sy(b.body.y), 15, -1);
    }
    // Projectiles.
    for (game.projectiles[0..game.projectile_count]) |p| {
        if (p.removed) continue;
        if (p.laser) {
            art.sprAt(art.LASER, p.age, art.sx(p.body.x), art.sy(p.body.y), 5, 9, false);
        } else {
            art.spr(art.BOULDER, p.age, art.sx(p.body.x), art.sy(p.body.y), 8, -1);
        }
    }
    // Elements.
    for (game.effects[0..game.effect_count]) |e| {
        var idx: u8 = 0;
        if (e.element != .none) {
            idx = art.ELEM[@intFromEnum(e.element)];
            if (e.element == .fire and e.body.ground) idx = art.FLAME;
        }
        if (idx != 0) art.sprAt(idx, e.age, art.sx(e.body.x), art.sy(e.body.y), 13, 11, e.dir > 0);
    }
    // Players.
    var pi: u8 = 0;
    while (pi < game.player_count) : (pi += 1) {
        const p = game.players[pi];
        if (p.lives == 0 and p.dead == 0) continue;
        if (p.invincible == 0 or @mod(p.invincible, 12) < 6) {
            var st: u8 = 0;
            var tick = p.walk_frame;
            if (!p.body.ground) {
                st = 1;
                tick = game.tick;
            }
            if (p.shoot > 0) {
                st = 2;
                tick = 12 - p.shoot;
            }
            if (p.dead > 0) {
                st = 3;
                tick = 90 - p.dead;
            }
            const av: u8 = if (game.player_count == 2) (@as(u8, 1) - pi) else profile().avatar;
            art.spr(art.PLAYER[av][st], tick, art.sx(p.body.x), art.sy(p.body.y), 16, p.dir);
        }
    }
    // Score pop-ups.
    for (game.particles[0..game.particle_count]) |pt| {
        const x = art.sx(pt.body.x);
        const y = art.sy(pt.body.y);
        switch (pt.text) {
            .points => |v| {
                var buf: [12]u8 = undefined;
                const s = std.fmt.bufPrint(&buf, "{d}", .{v}) catch "";
                art.small(s, x, y, assets.YELLOW, assets.INK);
            },
            .one_up => art.small("1UP", x, y, assets.GREEN, assets.INK),
            .none => art.spr(art.POP, 0, x, y, 15, -1),
        }
    }
    drawHud();
    // The Go's banners.
    if (game.state == .ready) {
        var buf: [24]u8 = undefined;
        const t = std.fmt.bufPrint(&buf, "ROUND {d:0>2}", .{game.level.number}) catch "";
        art.banner(t, "GET READY", art.PLAY_Y + 84);
    }
    if (game.state == .clearing) {
        var buf: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "COLLECT YOUR BONUS  {d}", .{@divTrunc(game.countdown + 59, 60)}) catch "";
        art.banner("ROUND CLEAR!", s, art.PLAY_Y + 20);
    }
    if (game.hurry and game.state == .playing and game.level_ticks < 33 * 60 and @mod(game.tick, 30) < 24) {
        art.banner("HURRY UP!", "", art.PLAY_Y + 84);
    }
    if (game.freeze > 0) {
        var buf: [24]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "TIME STOP {d}", .{@divTrunc(game.freeze + 59, 60)}) catch "";
        art.smallCenter(s, art.PLAY_Y + 4, assets.YELLOW, assets.INK);
    }
}

fn drawHud() void {
    const p = profile();
    // --- top band: round, score ---
    art.box(0, 0, art.SCR_W, art.PLAY_Y, assets.INK);
    var buf: [32]u8 = undefined;
    const round = std.fmt.bufPrint(&buf, "ROUND {d:0>2}", .{game.level.number}) catch "";
    art.text(round, 6, 6, assets.YELLOW, assets.INK);
    art.text("BUBBLE BOBBLE", 152, 6, assets.GREEN, assets.INK);
    art.small("SCORE", 290, 4, assets.MUTED, assets.INK);
    art.text(buf7(game.score), 290, 14, assets.WHITE, assets.INK);

    // --- left panel: the dragon, lives, enemies ---
    const av: u8 = if (game.player_count == 2) 0 else p.avatar;
    art.spr(art.PLAYER[av][0], frame, 20, 44, 32, -1);
    art.small("LIVES", 4, 84, assets.MUTED, assets.INK);
    art.spr(art.PLAYER[av][0], 0, 4, 94, 12, -1);
    const lives = std.fmt.bufPrint(&buf, "x{d}", .{game.players[0].lives}) catch "";
    art.text(lives, 22, 96, assets.WHITE, assets.INK);
    art.small("ENEMIES", 4, 120, assets.MUTED, assets.INK);
    const rem = std.fmt.bufPrint(&buf, "{d:0>2}", .{game.remainingEnemies()}) catch "";
    art.text(rem, 4, 130, assets.GREEN, assets.INK);
    art.small("ROUND", 4, 154, assets.MUTED, assets.INK);
    const r2 = std.fmt.bufPrint(&buf, "{d:0>2}", .{game.level.number}) catch "";
    art.text(r2, 4, 164, assets.WHITE, assets.INK);

    // --- right panel: powers, high score ---
    art.small("POWER", 332, 44, assets.MUTED, assets.INK);
    {
        const pw = game.players[0].power;
        var py: i32 = 56;
        if (pw.pink) {
            art.spr(art.POWER[1], 0, 340, py, 11, -1);
            py += 14;
        }
        if (pw.blue) {
            art.spr(art.POWER[2], 0, 340, py, 11, -1);
            py += 14;
        }
        if (pw.yellow) {
            art.spr(art.POWER[3], 0, 340, py, 11, -1);
            py += 14;
        }
        if (pw.shoes) {
            art.spr(art.POWER[4], 0, 340, py, 11, -1);
            py += 14;
        }
        if (pw.crystal) {
            art.spr(art.POWER[8], 0, 340, py, 11, -1);
            py += 14;
        }
        if (pw.amethyst) {
            art.spr(art.POWER[9], 0, 340, py, 11, -1);
            py += 14;
        }
        if (pw.ruby) {
            art.spr(art.POWER[10], 0, 340, py, 11, -1);
            py += 14;
        }
    }
    art.small("BEST", 332, 190, assets.PINK, assets.INK);
    art.text(buf7(@max(game.score, p.high_score)), 332, 200, assets.WHITE, assets.INK);

    // --- bottom band ---
    art.box(0, art.PLAY_Y + art.PLAY_H, art.SCR_W, art.SCR_H - (art.PLAY_Y + art.PLAY_H), assets.INK);
    art.small("ARROWS MOVE   SPACE BUBBLE   UP JUMP   ESC PAUSE   M SOUND", 60, 254, assets.MUTED, assets.INK);
}

// --------------------------------------------------------------------------
// --------------------------------------------------------------------------
// The harness's door into the pages: draw any of them without walking the
// menus, and read the palette back for screenshots.
// --------------------------------------------------------------------------
pub fn setPageForTest(n: u32) void {
    page = switch (n) {
        0 => .title,
        1 => .menu,
        2 => .profiles,
        3 => .new_profile,
        4 => .scores,
        5 => .settings,
        6 => .help,
        7 => .credits,
        8 => .editor,
        9 => .play,
        else => .result,
    };
    selected = 0;
}

pub fn pageForTest() u32 {
    return switch (page) {
        .title => 0,
        .menu => 1,
        .profiles => 2,
        .new_profile => 3,
        .scores => 4,
        .settings => 5,
        .help => 6,
        .credits => 7,
        .editor => 8,
        .play => 9,
        .result => 10,
    };
}

pub fn selectForTest(n: u32) void {
    selected = @intCast(n);
}

fn keyUp(cp: u32) callconv(.c) void {
    noteKeyUp(cp);
}

comptime {
    if (@import("../cart.zig").Cart == Demo) {
        _ = @import("bubblebobble/testapi.zig");
        @export(&keyUp, .{ .name = "keyUp" });
    }
}

