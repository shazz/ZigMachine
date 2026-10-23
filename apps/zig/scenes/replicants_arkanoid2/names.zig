// --------------------------------------------------------------------------
// The crew names, HOFA, SHOGUN, A-TEAM, one at a time: each letter is a 30x30
// tile (15x15 here) riding mycurve, the letters 10 curve entries (5 frames)
// apart. go():
//
//   tile i of an n-letter word at mycurve[(sprpos + 10*(n-1-i)) % 710], drawn
//   in order i = 0..n-1, so the LAST letter (at sprpos itself) is on top;
//   sprpos += 2; past 700 it returns to 0 and the next word comes up.
//
// Draw order with the scroller: go() draws the strip first, then the letters,
// so the letters pass over the scrolltext (the curve reaches y 398 = ST 199).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const art = @import("art.zig");
const curve = @import("curve.zig");

pub const TILE: usize = 15; // initTile(30,30,0)
const TRAIL: usize = 10; // curve entries between two letters
const STEP: u16 = 2; // sprpos += 2
const LAST: u16 = 700; // if (sprpos > 700) sprpos = 0, next word
const MAX_TILES = 6;

const Word = struct { img: blit.Image, tiles: usize };
pub const WORDS = [3]Word{
    .{ .img = art.hofa, .tiles = 4 },
    .{ .img = art.shogun, .tiles = 6 },
    .{ .img = art.ateam, .tiles = 6 },
};

const Pos = struct { x: i16, y: i16 };

pub const Names = struct {
    sprpos: u16,
    name: u8,
    // what the next render draws (go() draws, then advances)
    draw_pos: u16,
    draw_name: u8,
    // the boxes drawn last frame: restored before anything is drawn again
    drawn: [MAX_TILES]Pos,
    n_drawn: usize,

    pub fn init(self: *Names) void {
        self.sprpos = 0;
        self.name = 0;
        self.draw_pos = 0;
        self.draw_name = 0;
        self.n_drawn = 0;
    }

    pub fn step(self: *Names) void {
        self.draw_pos = self.sprpos;
        self.draw_name = self.name;
        self.sprpos += STEP;
        if (self.sprpos > LAST) {
            self.sprpos = 0;
            self.name = (self.name + 1) % @as(u8, WORDS.len);
        }
    }

    /// Letter i's top-left this frame.
    pub fn letterAt(self: *const Names, i: usize) Pos {
        const n = WORDS[self.draw_name].tiles;
        const k = (self.draw_pos + TRAIL * (n - 1 - i)) % curve.WRAP;
        return .{ .x = curve.st[k], .y = curve.st[k + 1] };
    }

    pub fn erase(self: *const Names, dst: blit.Dst) void {
        for (self.drawn[0..self.n_drawn]) |p| art.restore(dst, p.x, p.y, TILE, TILE);
    }

    pub fn draw(self: *Names, dst: blit.Dst) void {
        const word = WORDS[self.draw_name];
        for (0..word.tiles) |i| {
            const p = self.letterAt(i);
            const cell = blit.Rect{ .x = i * TILE, .y = 0, .w = TILE, .h = TILE };
            blit.blit(dst, word.img, cell, p.x, p.y, 0, .copy);
            self.drawn[i] = p;
        }
        self.n_drawn = word.tiles;
    }
};
