// The Union Demo hidden screen (screens/textracker/screen.js), replayed in JS at
// 320x200 for apps/union_textracker_headless.mjs, plus the mouse path both that
// harness and the Chrome reference capture of the original drive it with.
//
// The replay follows screen.js, not the scene: rastCnt = frame % 84 after the
// frame's update(); mousePos[k] is the position k updates ago (0 before the first);
// draw = raster quad, menu over it, tiles 3,2,1 at mousePos[24,16,8], the 8x8 quad
// at mousePos[0], tile 0 over it at globalAlpha 0.9. It reads the converted
// assets (screen.raw = menu + sheet, pal.dat); the conversion itself was checked
// against Chrome running the remake's own PNGs.

/// The mouse at screen frame `frame` (1 = the first update+draw), 320x200 units.
/// Self-contained: the reference capture serialises it into the page.
export function mouseAt(frame) {
    // [frame, x, y]: parked at (0,0) as the original starts, across the logo's
    // raster holes, into the bottom-right corner (clipping) and back.
    const WAYPOINTS = [[1, 0, 0], [40, 0, 0], [80, 200, 50], [120, 250, 52], [150, 160, 44],
        [180, 316, 196], [220, 100, 120], [260, 168, 46], [300, 319, 199]];
    let i = 0;
    while (i < WAYPOINTS.length - 2 && frame > WAYPOINTS[i + 1][0]) i++;
    const [f0, x0, y0] = WAYPOINTS[i], [f1, x1, y1] = WAYPOINTS[i + 1];
    const k = Math.min(Math.max(frame - f0, 0), f1 - f0);
    return [x0 + Math.trunc((x1 - x0) * k / (f1 - f0)), y0 + Math.trunc((y1 - y0) * k / (f1 - f0))];
}

/// Frames compared pixel for pixel; 84 and 85 straddle the raster table's wrap.
export const SHOTS = [1, 40, 60, 84, 85, 100, 121, 125, 151, 185, 230, 262, 300];

// screen.js:28-39, transcribed separately from the scene.
const RASTER_COLORS = [
    "#F00", "#F10", "#F20", "#F30", "#F40", "#F50", "#F60", "#F70",
    "#F80", "#F90", "#FA0", "#FB0", "#FC0", "#FD0", "#FE0", "#FF0",
    "#DF0", "#DF0", "#BF0", "#BF0", "#9F0", "#9F0", "#7F0", "#7F0",
    "#4F0", "#4F0", "#2F0", "#2F0", "#0F0", "#0F0", "#0F2", "#0F2",
    "#0F4", "#0F4", "#0F7", "#0F7", "#0F9", "#0F9", "#0FB", "#0FB",
    "#0FD", "#0FD", "#0FF", "#0FF", "#0DF", "#0DF", "#0BF", "#0BF",
    "#09F", "#09F", "#07F", "#07F", "#04F", "#04F", "#02F", "#02F",
    "#00F", "#00F", "#20F", "#20F", "#40F", "#40F", "#70F", "#70F",
    "#90F", "#90F", "#B0F", "#B0F", "#D0F", "#D0F", "#F0F", "#F0F",
    "#F0D", "#F0D", "#F0B", "#F0B", "#F09", "#F09", "#F07", "#F07",
    "#F04", "#F04", "#F02", "#F02"];
const css = (s) => [1, 2, 3].map((i) => parseInt(s[i], 16) * 17);

const W = 320, H = 200, TILE = 16, SHEET_W = 64;
const HOLE = 12; // the menu's transparent index, as converted

/// One channel of tile 0 drawn at globalAlpha 0.9 over an opaque pixel, as Chrome
/// does it (fitted to the reference frames, every tile-0 channel exact): alpha
/// 230, source x231 >> 8 plus destination x26 >> 8.
export function mix09(s, d) {
    return ((s * 231) >> 8) + ((d * 26) >> 8);
}

/// `opts.trailStep` / `opts.mix` exist to prove the harness fails on a wrong port.
export function makeReplay(screenRaw, palDat, opts = {}) {
    const trailStep = opts.trailStep ?? 8, mix = opts.mix ?? mix09;
    const menu = screenRaw.subarray(0, W * H), sheet = screenRaw.subarray(W * H);
    const pal = (i) => [palDat[i * 4], palDat[i * 4 + 1], palDat[i * 4 + 2]];
    const pos = (f, k) => (f - k >= 1 ? mouseAt(f - k) : [0, 0]);

    return function frame(f) {
        const raster = css(RASTER_COLORS[f % RASTER_COLORS.length]);
        const rgb = new Uint8Array(W * H * 3);
        const put = (x, y, c) => { if (x >= 0 && x < W && y >= 0 && y < H) rgb.set(c, (y * W + x) * 3); };
        for (let i = 0; i < W * H; i++) rgb.set(menu[i] === HOLE ? raster : pal(menu[i]), i * 3);
        const tile = (n, [px, py], ink) => {
            for (let y = 0; y < TILE; y++) for (let x = 0; x < TILE; x++) {
                const v = sheet[y * SHEET_W + n * TILE + x];
                if (v !== 0) put(px + x, py + y, ink(v, px + x, py + y));
            }
        };
        for (let n = 3; n > 0; n--) tile(n, pos(f, n * trailStep), (v) => pal(v));
        const [mx, my] = pos(f, 0);
        for (let y = 0; y < 4; y++) for (let x = 0; x < 4; x++) put(mx + x, my + y, raster);
        tile(0, [mx, my], (v, x, y) => {
            const o = (y * W + x) * 3, s = pal(v);
            return s.map((c, i) => mix(c, rgb[o + i]));
        });
        return rgb;
    };
}
