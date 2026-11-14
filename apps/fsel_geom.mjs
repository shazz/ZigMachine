// The ITEM SELECTOR's committed layout (rom/gem/desktop/fsel_geom.zig: `ours`), for the harnesses that
// click it and check where it draws: gemtest_fsel_check.mjs, filesel_check.mjs, notepad_fsel_check.mjs.
// Our own numbers (cells of the font height ch + pixels), never a local asset build's geometry: these
// harnesses run against the committed ROM. Every rect is on the screen (the box centred as the ROM does).
export const cellFor = (sh) => (sh >= 400 ? 16 : 8);

export function fselGeom(sw, sh) {
    const c = cellFor(sh), pad = (c >> 1) + 4, barY = 4 * c + 16, sy = 3 * c + 12, arrow = 2 * c, dy = c + 5;
    const list = { x: 24, y: barY + c + 1, w: 158, h: 11 * c };
    const drives = { x: 216, y: barY, w: 80, h: 8 * dy };
    const by = Math.max(list.y + list.h, drives.y + drives.h) + (pad >> 1) + 2;
    const w = 312, h = by + c + 2 + pad, bx = (sw - w) >> 1, byy = Math.max(0, (sh - h) >> 1);
    const at = (r) => ({ x: bx + r.x, y: byy + r.y, w: r.w, h: r.h });
    const mid = (r) => [r.x + (r.w >> 1), r.y + (r.h >> 1)];
    const g = {
        ch: c, box: { x: bx, y: byy, w, h }, titleY: byy + (c >> 3) + 4,
        dirLabel: at({ x: 8, y: (c >> 3) + c + 6, w: 80, h: c }), dir: at({ x: 8, y: 2 * c + 8, w: 296, h: c }),
        sel: at({ x: 96, y: sy, w: 96, h: c }), driveLabel: at({ x: 232, y: sy, w: 48, h: c }),
        closer: at({ x: 24, y: barY, w: 16, h: c + 2 }), list: at(list),
        row: (i) => at({ x: list.x + 8, y: list.y + c + i * c, w: 120, h: c }),
        up: at({ x: 181, y: list.y, w: 24, h: arrow }), down: at({ x: 181, y: list.y + list.h - arrow, w: 24, h: arrow }),
        drive: (k) => at({ x: drives.x + 4 + (k % 2) * 40, y: drives.y + (k >> 1) * dy, w: 32, h: c + 2 }),
        ok: at({ x: 64, y: by, w: 72, h: c + 2 }), cancel: at({ x: 176, y: by, w: 72, h: c + 2 }),
    };
    g.mid = mid;
    return g;
}
