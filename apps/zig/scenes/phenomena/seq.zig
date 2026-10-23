// --------------------------------------------------------------------------
// screen.js's chain of requestAnimationFrame functions, one call a frame:
//
//   showTextPage1   rasterbarY -40 .. 340 by 1.5           (254 frames)
//   showTextPage2   percent 0..200 by 1, then 100..0 by -1
//   showLogo        silhouette hsl(0 0% p%), p 0..100 by 4; then the logo
//                   under a white silhouette at alpha (200-p)/100, p 104..198 by 2
//   showUpperRasterbar / showLowerRasterbar   alpha p/100, p 0..96 by 4
//                   (the lower one starts 'rasta man.mod')
//   dropPhoton      the drop table (139 frames)
//   photonFadeToRed hsl(0 100% p%), p 100..52 by -4
//   go()            drawGraphics, for ever
//
// Each function draws, advances, and on its last frame calls the next one
// directly, which draws over it in the same frame. So `step` records what the
// frame shows (`view`) and chains exactly the same way; app.zig paints it.
// hideLogo / hideLowerRasterbar / hideUpperRasterbar are not here: go()'s
// call to them is commented out in screen.js, so the remake never fades out.
// --------------------------------------------------------------------------
const T = @import("tables.zig");
const dna = @import("dna.zig");

pub const Phase = enum(u8) { page1, page2, logo, bar_top, bar_bottom, drop, fade, main };

pub const View = struct {
    phase: Phase,
    level: i32, // percent as drawn (page 2, logo, bars, fade)
    rb2: i32, // 2 * rasterbarY as drawn (page 1)
    photon: i32, // first canvas row of the photon (drop, fade, main)
    hue: u32, // floor(color) (main)
    rect_w: i32, // the reveal quad's width as drawn, <= 0 = none (main)
    t: u32, // main frames so far: t = 0.30 * t (main)
};

pub var phase: Phase = .page1;
pub var percent: i32 = 0;
pub var direction: i32 = 1;
pub var rb2: i32 = -80;
pub var drop_n: u16 = 0;
pub var color3: u32 = 0; // color * 3 (color += 1/3 a frame)
pub var t: u32 = 0;
pub var rect_w: i32 = 640;
pub var rect_show: bool = true;
pub var music_due: bool = false;
pub var view: View = undefined;

pub fn reset() void {
    phase = .page1;
    percent = 0;
    direction = 1;
    rb2 = -80;
    drop_n = 0;
    color3 = 0;
    t = 0;
    rect_w = 640;
    rect_show = true;
    music_due = false;
    view = .{ .phase = .page1, .level = 0, .rb2 = rb2, .photon = 0, .hue = 0, .rect_w = 0, .t = 0 };
}

fn show(p: Phase, level: i32) void {
    phase = p;
    view = .{ .phase = p, .level = level, .rb2 = 0, .photon = 0, .hue = 0, .rect_w = 0, .t = 0 };
}

pub fn step() void {
    switch (phase) {
        .page1 => page1(),
        .page2 => page2(),
        .logo => logo(),
        .bar_top => barTop(),
        .bar_bottom => barBottom(),
        .drop => drop(),
        .fade => fade(),
        .main => main(),
    }
}

fn page1() void {
    show(.page1, 0);
    view.rb2 = rb2;
    rb2 += 3;
    if (rb2 >= 680) {
        rb2 = 0;
        percent = 0;
        page2();
    }
}

fn page2() void {
    show(.page2, percent);
    percent += direction;
    if (percent > 200) {
        direction = -1;
        percent = 100;
    }
    if (percent <= 0 and direction == -1) {
        percent = 0;
        logo();
    }
}

fn logo() void {
    show(.logo, percent);
    percent += if (percent <= 100) 4 else 2;
    if (percent >= 200) {
        percent = 0;
        barTop();
    }
}

fn barTop() void {
    show(.bar_top, percent);
    percent += 4;
    if (percent >= 100) {
        percent = 0;
        barBottom();
    }
}

fn barBottom() void {
    show(.bar_bottom, percent);
    percent += 4;
    if (percent >= 100) {
        percent = 0;
        music_due = true; // audRastaman.LoadAndRun('rasta man.mod')
        drop();
    }
}

fn drop() void {
    show(.drop, 0);
    view.photon = T.DROP[drop_n];
    drop_n += 1;
    if (drop_n == T.DROP.len) { // photonBounce >= -0.70
        percent = 100;
        fade();
    }
}

fn fade() void {
    show(.fade, percent);
    view.photon = 445;
    percent -= 4;
    if (percent < 50) {
        percent = 0;
        main();
    }
}

/// drawGraphics.
fn main() void {
    show(.main, 0);
    view.photon = 445;
    view.hue = color3 / 3;
    color3 += 1;
    if (color3 > 360 * 3) color3 = 0;
    dna.tick();
    t += 1;
    dna.turn(dna.rot_speed);
    view.t = t;
    view.rect_w = if (rect_show) rect_w else 0;
    if (rect_show) {
        if (rect_w >= 0) {
            rect_w -= 8;
        } else {
            rect_w = 0;
            rect_show = false;
        }
    }
}
