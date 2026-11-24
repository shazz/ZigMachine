// The tub of one back half, in the LEFT-half frame: u = X from the outer side, v = Y - tray_d from the
// joint face, z up. The right half is this mirrored. The joint face (v = 0) is open, like the reference.

module screw_post(u, v) { translate([u, v, 0]) cylinder(d = post_d, h = case_h, $fn = 40); }

module along_y_hole(u, z) {   // blind hole into the joint face
    translate([u, -1, z]) rotate([-90, 0, 0]) cylinder(d = joint_hole_d, h = joint_hole_depth + 1, $fn = 24);
}

module along_x_hole(v) {      // blind hole into the centre face
    translate([half_w + 1, v, centre_hole_z]) rotate([0, -90, 0])
        cylinder(d = centre_hole_d, h = centre_hole_depth + 1, $fn = 24);
}

module shell_local() {
    difference() {
        union() {
            cube([half_w, back_d, floor_t]);
            cube([wall, back_d, case_h]);                                   // outer side
            translate([half_w - wall, 0, 0]) cube([wall, back_d, case_h]);  // centre
            translate([0, back_d - wall, 0]) cube([half_w, wall, case_h]);  // back wall
            for (c = cover_posts) screw_post(c[0], c[1]);
            // joint pillars: the outer one is a block fused to the side wall, the inner one is the corner post
            translate([wall, 0, 0]) cube([joint_hole_from_side + post_d / 2 - wall, joint_depth(), case_h]);
            for (v = centre_hole_v)
                translate([half_w - centre_hole_depth, v - post_d / 2, 0]) cube([centre_hole_depth, post_d, case_h]);
        }
        along_y_hole(joint_hole_from_side, joint_hole_z);
        along_y_hole(half_w - joint_hole_from_centre, joint_hole_z);
        for (v = centre_hole_v) along_x_hole(v);
        for (c = cover_posts)
            translate([c[0], c[1], case_h - cover_pilot_depth]) cylinder(d = cover_pilot_d, h = cover_pilot_depth + 1, $fn = 24);
    }
}

function joint_depth() = joint_hole_depth;

module structure(side) {
    translate([0, tray_d, 0]) {
        if (side == 0) shell_local();
        else translate([case_w, 0, 0]) mirror([1, 0, 0]) shell_local();
    }
}

module half_box(side) { translate([side * half_w, tray_d - 1, -1]) cube([half_w, back_d + 2, case_h + 2]); }

// print = true: the part lies at the origin (min corner), ready for the slicer
module back_half(side, print = false) {
    off = print ? [-side * half_w, -tray_d, 0] : [0, 0, 0];
    translate(off) intersection() {
        half_box(side);
        difference() {
            union() { structure(side); features_add(); }
            features_cut();
        }
    }
}
