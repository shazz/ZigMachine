// KESTREL case: OUR back (electronics) parts + top covers, drawn from scratch.
// The front (keyboard tray) is a third-party STL printed as is; see README.md / PLAN.md "Model v1".
// Render one part:  openscad -D 'part="back_left"' -o stl/back_left.stl kestrel_case.scad
// Frame (assembly): X 0..case_w across (left half 0..case_w/2), Y 0 = front edge of the tray,
// Y = tray_d is the tray|electronics joint, Y = tray_d + back_d = back wall outside; Z up.
include <lib/params_ports.scad>
include <lib/ghosts.scad>
include <lib/ports.scad>
include <lib/structure.scad>
include <lib/layout_features.scad>
include <lib/cover.scad>

/* [Part] */
// all = assembly view (every part in place); the others come out in their PRINT position (at the origin)
part = "all"; // [all, back_left, back_right, top_left, top_right]
// ghosts of the board, hub, iCode, keyboard
show_ghosts = true;
// draw the two covers (translucent) in the assembly
show_covers = true;
// the third-party front STLs (prototypes/ is untracked; a missing file only gives a warning)
show_reference_front = true;
// remove a slab of the back parts near the joint, to look inside
section_cut = false;

module assembly() {
    difference() {
        union() {
            back_half(0); back_half(1);
            if (show_covers) color("khaki", 0.35) { cover_in_place(0); cover_in_place(1); }
            if (show_ghosts) ghosts();
        }
        if (section_cut) translate([-1, tray_d + 60, case_h - 10]) cube([case_w + 2, 120, 30]);
    }
}

if (part == "all") assembly();
else if (part == "back_left") back_half(0, print = true);
else if (part == "back_right") back_half(1, print = true);
else if (part == "top_left") cover(0);
else if (part == "top_right") cover(1);
