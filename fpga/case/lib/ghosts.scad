// Assembly-view ghosts only (never exported): board, hub, iCode, keyboard, the reference front parts.
// The reference STLs are third-party and untracked: prototypes/kestrel_case/. Missing file = a warning only.
ref_dir = "../../prototypes/kestrel_case/";
ref_front_left = str(ref_dir, "front left.STL");
ref_front_right = str(ref_dir, "front right.STL");
kb_slope = atan((case_h - 14) / tray_d);   // the wedge rises from ~14 (front) to 49 (joint)

module ghosts() {
    color("seagreen", 0.5) translate([board_x, board_y, floor_t + standoff_h]) {
        cube([board_w, board_d, board_pcb]);
        translate([board_w / 2 - 8, board_d - 21, board_pcb]) cube([16, 21, board_tall]);   // RJ45 (tallest)
    }
    color("steelblue", 0.5) translate([hub_x, hub_y, floor_t]) cube([hub_w, hub_d, hub_h]);
    color("orange", 0.5) translate([icode_x, icode_y, floor_t]) cube([icode_w, icode_d, icode_h]);
    color("lightsteelblue", 0.45) translate([kb_x, kb_y, 14 + (case_h - 14) * kb_y / tray_d])
        rotate([kb_slope, 0, 0]) cube([kb_w, kb_d, kb_h]);
    if (show_reference_front) {
        // reference parts lie with x = depth (joint at x = 1.2), y = width, z = height
        %multmatrix([[0, 1, 0, -0.85], [-1, 0, 0, 158.2], [0, 0, 1, 0], [0, 0, 0, 1]]) import(ref_front_left);
        %multmatrix([[0, 1, 0, 185.65], [-1, 0, 0, 158.2], [0, 0, 1, 0], [0, 0, 0, 1]]) import(ref_front_right);
    }
}
