// Panel cut-outs: one opening + 2 screw holes + an engraved label per port.
// Local frame of a port: x along the wall, y = outward normal (outer face at y = 0), z up (0 = port_z).

function kind_sp(k) = k == "usbc" ? usbc_sp : k == "usba" ? usba_sp : k == "hdmi" ? hdmi_sp
    : k == "rj45" ? rj45_sp : k == "db9" ? db9_sp : k == "sd" ? sd_sp : 0;

module rounded_slot(w, h) { hull() for (s = [-1, 1]) translate([s * (w - h) / 2, 0]) circle(d = h, $fn = 24); }

module opening_2d(k) {
    c = clear;
    if (k == "usbc") rounded_slot(usbc_w + c, usbc_h + c);
    else if (k == "usba") square([usba_w + c, usba_h + c], center = true);
    else if (k == "hdmi") square([hdmi_w + c, hdmi_h + c], center = true);
    else if (k == "rj45") square([rj45_w + c, rj45_h + c], center = true);
    else if (k == "jack") circle(d = jack_d, $fn = 40);
    else if (k == "sd") rounded_slot(sd_w, sd_h);
    else if (k == "db9") {
        w = db9_w + c; h = db9_h + c; dx = h * tan(10);   // slanted D shape, wide side up
        polygon([[-w / 2, h / 2], [w / 2, h / 2], [w / 2 - dx, -h / 2], [-w / 2 + dx, -h / 2]]);
    }
}

// extrude a 2D (x,z) shape from y = +1 (outside) inward by depth
module through(depth) { translate([0, 1, 0]) rotate([90, 0, 0]) linear_extrude(depth + 1) children(); }

module port_cut(k) {
    through(wall + 2) opening_2d(k);
    sp = kind_sp(k);
    if (sp > 0) for (s = [-1, 1]) translate([s * sp / 2, 0, 0]) through(wall + 2) circle(d = screw_d, $fn = 24);
    if (k == "sd") sd_floppy_styling();
}

// Atari ST floppy look around the SD slot: a recessed bezel, an eject button recess and a finger notch
module sd_floppy_styling() {
    through(sd_bezel_depth) square([sd_bezel_w, sd_bezel_h], center = true);
    translate([sd_bezel_w / 2 - 7, 0, -sd_h / 2 - 3]) through(sd_bezel_depth + 0.6) circle(d = 5, $fn = 24);
    translate([0, 0, sd_h / 2 + 2.2]) through(sd_bezel_depth + 0.6) square([8, 1.6], center = true);
}

module port_label(txt) {
    // text is mirrored in x so it reads correctly from OUTSIDE the wall
    translate([0, 0.01, label_dz]) rotate([90, 0, 0]) mirror([1, 0, 0])
        linear_extrude(label_depth + 0.01) text(txt, size = label_size, halign = "center", valign = "center");
}

module at_wall(wall_name, pos) {
    if (wall_name == "back") translate([pos, tray_d + back_d, port_z]) children();
    else if (wall_name == "left") translate([0, pos, port_z]) rotate([0, 0, 90]) children();
    else translate([case_w, pos, port_z]) rotate([0, 0, -90]) children();
}

module all_ports() {
    for (p = ports) at_wall(p[1], p[2]) {
        port_cut(p[3]);
        port_label(p[0]);
    }
}
