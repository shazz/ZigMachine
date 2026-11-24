// Top covers (one per half), lying flat as printed. Local frame as shell_local(), v from the joint face;
// the cover reaches cover_overlap in front of it (v < 0). Vents over the board and the name on the left one.

module vent_slots() {
    u0 = board_x + (board_w - (vent_n - 1) * vent_pitch) / 2;
    vc = board_y + board_d / 2 - tray_d;
    for (i = [0 : vent_n - 1])
        translate([u0 + i * vent_pitch - vent_w / 2, vc - vent_len / 2, -1]) cube([vent_w, vent_len, cover_t + 2]);
}

module cover_local(side) {
    difference() {
        translate([0, -cover_overlap, 0]) cube([half_w, back_d + cover_overlap, cover_t]);
        for (c = cover_posts) {
            translate([c[0], c[1], -1]) cylinder(d = cover_hole_d, h = cover_t + 2, $fn = 24);
            translate([c[0], c[1], cover_t - 1.5]) cylinder(d = cover_cbore_d, h = 2, $fn = 24);
        }
        if (side == 0) {
            vent_slots();
            translate([60, 40, cover_t - name_depth]) linear_extrude(name_depth + 0.1)
                text(name_text, size = name_size, halign = "center", valign = "center");
        }
    }
}

// print position: min corner at the origin
module cover(side) {
    if (side == 0) translate([0, cover_overlap, 0]) cover_local(0);
    else translate([half_w, cover_overlap, 0]) mirror([1, 0, 0]) cover_local(1);
}

module cover_in_place(side) {
    if (side == 0) translate([0, tray_d, case_h]) cover_local(0);
    else translate([case_w, tray_d, case_h]) mirror([1, 0, 0]) cover_local(1);
}
