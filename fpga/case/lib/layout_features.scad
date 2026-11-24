// What the top-view layout puts inside: board standoffs, hub / iCode trays, cable-loop guides.
// Assembly frame; each half takes its share through the intersection in back_half().

function board_hole_pts() = [for (x = [board_x + board_hole_edge, board_x + board_w - board_hole_edge],
                                  y = [board_y + board_hole_edge, board_y + board_d - board_hole_edge]) [x, y]];

module standoffs() {
    for (p = board_hole_pts()) translate([p[0], p[1], 0]) cylinder(d = standoff_d, h = floor_t + standoff_h, $fn = 32);
}

module insert_holes() {
    for (p = board_hole_pts())
        translate([p[0], p[1], floor_t + standoff_h - insert_depth]) cylinder(d = insert_d, h = insert_depth + 1, $fn = 24);
}

// four L-shaped corner clips: the 4 sides stay open for the cables
module corner_clips(x, y, w, d, h = tray_clip_h) {
    s = tray_slop; t = tray_clip_t; l = tray_clip_len;
    for (sx = [0, 1], sy = [0, 1]) {
        translate([sx ? x + w + s - l : x - s - t, sy ? y + d + s : y - s - t, floor_t - 0.01]) cube([l + t, t, h]);
        translate([sx ? x + w + s : x - s - t, sy ? y + d + s - l : y - s - t, floor_t - 0.01]) cube([t, l + t, h]);
    }
}

module strap_slots(x, y, w, d) {   // zip-tie slots through the floor under a part
    for (fx = [0.25, 0.75]) translate([x + w * fx - strap_w / 2, y + d / 2 - strap_l / 2, -1]) cube([strap_w, strap_l, floor_t + 2]);
}

function clampv(v, lo, hi) = min(max(v, lo), hi);

// semicircular guide (cable runs round the OUTSIDE of radius loop_r) with an overhanging lip on top
module loop_guide(cx, cy, dir) {
    rl = loop_r + loop_lip; m = wall + loop_margin;
    horiz = dir == "left" || dir == "right";
    x = horiz ? clampv(cx, m + (dir == "right" ? rl : 0), case_w - m - (dir == "left" ? rl : 0)) : clampv(cx, m + rl, case_w - m - rl);
    ylo = tray_d + (dir == "up" ? rl : 0) + (horiz ? rl : 0);
    yhi = tray_d + back_d - m - (dir == "down" ? rl : 0) - (horiz ? rl : 0);
    y = clampv(cy, ylo, yhi);
    ang = dir == "up" ? 0 : dir == "left" ? 90 : dir == "down" ? 180 : 270;
    // the ring starts 1 mm inside the floor (no coplanar faces) and is hollow: the floor is the structure's
    translate([x, y, floor_t - 1]) rotate([0, 0, ang]) {
        difference() {
            union() {
                cylinder(r = loop_r, h = loop_h, $fn = 90);
                translate([0, 0, loop_h - 2]) cylinder(r = rl, h = 2, $fn = 90);
            }
            translate([0, 0, -1]) cylinder(r = loop_r - loop_wall, h = loop_h + 2, $fn = 90);
            translate([-rl - 1, 0, -2]) cube([2 * rl + 2, rl + 1, loop_h + 4]);   // keep the lower half
        }
    }
}

module features_add() {
    standoffs();
    corner_clips(hub_x, hub_y, hub_w, hub_d);
    corner_clips(icode_x, icode_y, icode_w, icode_d, tray_clip_h + 4);
    for (l = loops) loop_guide(l[1], l[2], l[3]);
}

module features_cut() {
    all_ports();
    insert_holes();
    strap_slots(hub_x, hub_y, hub_w, hub_d);
    strap_slots(icode_x, icode_y, icode_w, icode_d);
}
