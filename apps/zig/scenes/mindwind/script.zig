// --------------------------------------------------------------------------
// Mind Rewind's running order, as main ($0048-$00CC) calls it, one op a step.
// An op either acts at once or takes frames; `wait n` is the demo's $4F6.
// The parts wait on the song position ($771E); here those positions are frame
// counts from the music's start (apps/mindwind_music_check.mjs measures them
// on the SNDH: $4C@738 ... $242@7266), so the cart keeps time by itself.
// The second half replays the parts in reverse ($45AE, $8C00, $3606).
// --------------------------------------------------------------------------
pub const Fx = enum { none, flat, pulse, moire, blocks, swirl, bands, wobble, flip, full3, full2, full1, rewind_bands };
pub const Pal = enum { black, stripes, girl };
pub const Mode = enum { fader, rainbow, band }; // which palette the field shows (the kernel's choice)
pub const Call = enum { rewind_sfx, reverse_song };

pub const Op = union(enum) {
    run: struct { fx: Fx, frames: u16 },
    until: struct { fx: Fx, frame: u16 },
    fade: struct { to: Pal, speed: i8 },
    mode: Mode,
    bars_in, // $37FC: 17 frames
    bars_out, // $3878: 16 frames
    bars_now: u8, // $38A6 at a window step, at once
    bars_instant, // $382A: 2 frames, the bars drawn whole, VHS toggled
    blank_all, // $2056
    scroller: bool,
    scroller_slide, // $BB0C: 110 frames, the scroller from line 101 to 210
    scroller_reverse, // $BA90
    music: Call,
    vhs: bool,
    hook: bool, // $594 = $4818 (rainbow cycling) or 0
    field_blank, // field lines -> an empty image row
    reveal: u2, // $476C: about 91 frames
    flash_in, // $16F78: 17 frames
    flash_out, // $16FE8: 17 frames
    end,
};

// song positions, as frames from the music's start (mindwind_music_check.mjs)
const P4C = 738;
const P74 = 1122;
const P9C = 1506;
const PC4 = 1890;
const PEC = 2274;
const P114 = 2658;
const P160 = 3378;
const P1B6 = 4986;
const P1F0 = 5688;
const P20F = 6150;
const P226 = 6522;
const P242 = 7266;

fn w(n: u16) Op {
    return .{ .run = .{ .fx = .none, .frames = n } };
}

/// A first-half effect: fade in, run until the song position, fade out over `out` frames.
fn seg(fx: Fx, pal: Pal, speed: i8, until: u16, out: u16) [4]Op {
    return .{
        .{ .fade = .{ .to = pal, .speed = speed } },
        .{ .until = .{ .fx = fx, .frame = until } },
        .{ .fade = .{ .to = .black, .speed = speed } },
        .{ .run = .{ .fx = fx, .frames = out } },
    };
}

/// A second-half effect: fade in, run `n` frames, fade out over `out` frames.
fn rseg(fx: Fx, pal: Pal, speed: i8, n: u16, out: u16) [4]Op {
    return .{
        .{ .fade = .{ .to = pal, .speed = speed } },
        .{ .run = .{ .fx = fx, .frames = n } },
        .{ .fade = .{ .to = .black, .speed = speed } },
        .{ .run = .{ .fx = fx, .frames = out } },
    };
}

pub const ops = [_]Op{
    // $BAE8: the intro, the scroller alone in the middle, then sliding down
    .{ .mode = .fader }, .blank_all, .{ .scroller = true }, w(550), .scroller_slide,
    .{ .until = .{ .fx = .none, .frame = P4C } },
    // $340C: part A
    w(25), .bars_in, w(25), w(1),
} ++ seg(.flat, .stripes, 3, P74, 60) ++ seg(.pulse, .stripes, 3, P9C, 60) ++
    seg(.moire, .stripes, 3, PC4, 60) ++ seg(.blocks, .stripes, 3, PEC, 60) ++
    seg(.swirl, .stripes, 3, P114, 60) ++ seg(.bands, .stripes, 3, P160, 60) ++ [_]Op{
    .bars_out, w(20),
    // $8ACC: part B
    w(1),
} ++ seg(.wobble, .girl, 2, P1B6, 59) ++ [_]Op{w(1)} ++ seg(.flip, .girl, 2, P1F0, 59) ++ [_]Op{
    // $44D6: part C
    w(1), .blank_all, w(4), .bars_in, w(5), .{ .bars_now = 17 }, .{ .mode = .rainbow }, w(1),
    .{ .hook = true },                 .field_blank,
    .{ .reveal = 0 },                  .{ .until = .{ .fx = .none, .frame = P20F } },
    .{ .reveal = 1 },                  .{ .until = .{ .fx = .none, .frame = P226 } },
    .{ .reveal = 2 },                  .{ .until = .{ .fx = .none, .frame = P242 } },
    w(5),                              .bars_out,
    w(7),                              .{ .mode = .fader },
    .blank_all,
    // $2A4, $16EB8: the rewind
    .{ .music = .rewind_sfx },
    .{ .scroller = false },            .{ .mode = .band },
    .{ .hook = false },                .flash_in,
    .{ .run = .{ .fx = .rewind_bands, .frames = 70 } }, .flash_out,
    .{ .scroller = true },
    // $80E8 + $2F2 + $BA90: reversed samples, song 2, the scroller backwards
    .{ .music = .reverse_song },       .scroller_reverse,
    // $45AE: part C reversed
    .{ .mode = .fader },               .blank_all,
    w(7),                              w(1),
    .blank_all,                        w(4),
    .bars_in,                          w(5),
    .{ .bars_now = 17 },               .{ .mode = .rainbow },
    w(1),                              .{ .hook = true },
    .field_blank,                      .{ .vhs = true },
    .{ .run = .{ .fx = .full3, .frames = 101 } }, .{ .run = .{ .fx = .full2, .frames = 101 } },
    .{ .run = .{ .fx = .full1, .frames = 101 } }, .{ .mode = .fader },
    w(1),                              .blank_all,
    .{ .hook = false },
    // $8C00: part B reversed
    w(1),
} ++ rseg(.flip, .girl, 2, 201, 59) ++ [_]Op{w(1)} ++ rseg(.wobble, .girl, 2, 201, 59) ++ [_]Op{
    // $3606: part A reversed
    .bars_instant,
} ++ rseg(.bands, .stripes, 3, 51, 60) ++ rseg(.swirl, .stripes, 3, 51, 60) ++
    rseg(.blocks, .stripes, 3, 51, 60) ++ rseg(.moire, .stripes, 3, 51, 60) ++
    rseg(.pulse, .stripes, 3, 51, 60) ++ rseg(.flat, .stripes, 3, 51, 60) ++ [_]Op{
    .bars_out, w(20),
    // $418, $1AA: the end screen (and the rewind sound once more)
    .{ .music = .rewind_sfx }, .end,
};
