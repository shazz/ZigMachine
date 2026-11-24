// All dimensions (mm), grouped for the Customizer. Included first by kestrel_case.scad: top-level
// assignments of included files are evaluated in order, so the groups other files read live here.

/* [Case] */
case_w = 373;       // total width, split in the middle
tray_d = 157;       // keyboard tray depth (the reference front part, unchanged)
back_d = 170;       // electronics section depth (the reference is 120)
case_h = 49;        // wall height = the front parts' height
wall = 3;           // side / back wall
floor_t = 3;        // base plate
bed_x = 190;        // printer bed
bed_y = 180;

half_w = case_w / 2;

/* [Joint to the front parts (measured on the reference: tools/joint_analysis.py)] */
joint_hole_d = 3.15;           // blind holes in BOTH mating faces (reference: 3.15)
joint_hole_depth = 10;         // each side
joint_hole_z = 39;             // height of the two front/back holes
joint_hole_from_side = 11.0;   // outer one: from the outer side face
joint_hole_from_centre = 5.0;  // inner one: from the centre face
centre_hole_d = 3.15;          // holes between the left and right back halves (along X)
centre_hole_z = 29;
centre_hole_v = [5, 62, 119, 158.5];   // along the depth, from the joint face
centre_hole_depth = 10;
post_d = 10;                   // boss around every screw
cover_pilot_d = 2.75;          // self-tapping M3 pilot in the top of the posts (reference 2.75)
cover_hole_d = 3.2;            // through the cover
cover_cbore_d = 6;
cover_pilot_depth = 10;
// cover screw posts [u from the outer side face, v from the joint face], left-half frame. No outer mid post:
// it would sit on the WI-FI screw holes of the right wall.
cover_posts = [[6.5, 5], [181.5, 5], [6.5, 162.6], [181.5, 162.6], [181.5, 85]];

/* [Cover] */
cover_t = 4;               // plate thickness
cover_overlap = 6;         // how far the cover reaches over the front part (keeps it inside a 180 bed)
vent_n = 11;               // slots over the board
vent_w = 2.2;
vent_pitch = 5;
vent_len = 44;
name_text = "KESTREL";
name_size = 14;
name_depth = 1.2;

/* [Board (Z7-Lite) and inside parts] */
board_x = 112; board_y = 215; board_w = 60; board_d = 80;   // footprint (60 across, 80 deep)
board_pcb = 1.6;
board_tall = 14;           // RJ45, the tallest part above the PCB
standoff_h = 8;            // the SD extension plugs in underneath
standoff_d = 7;
board_hole_d = 3.2;
board_hole_edge = 2.6;     // hole centres from each edge
insert_d = 4.2;            // M3 heat-set insert hole
insert_depth = 6;
hub_x = 240; hub_y = 230; hub_w = 75; hub_d = 40; hub_h = 10;
icode_x = 12; icode_y = 175; icode_w = 90; icode_d = 40; icode_h = 20;
tray_slop = 1;             // gap between a part and its corner clips
tray_clip_len = 12; tray_clip_t = 1.6; tray_clip_h = 6;
strap_w = 3; strap_l = 14; // zip-tie slots in the floor
kb_x = 6.5; kb_y = 16; kb_w = 360; kb_d = 125; kb_h = 10;   // keyboard ghost (rests on the wedge)

/* [Cable loops: 6 cm U bends (inner radius 30)] */
loop_r = 30;               // inner bend radius = the guide's outer radius
loop_wall = 2;
loop_h = 26;
loop_lip = 4;              // the lip that keeps the cable on the guide
loop_margin = 1;           // clearance to the walls
// [label, centre x, centre y, direction the U opens]; moved from layout_topview.py so none overlaps or crosses a wall
loops = [["HDMI / RJ45", 85, 292, "right"], ["USB-C x3", 225, 190, "up"], ["USB2 x2", 335, 292, "left"],
         ["DB9 x2", 45, 245, "right"], ["SD / jack", 325, 185, "left"]];

/* [Port cut-outs (female shell W x H + clearance); screw spacings from PLAN.md] */
clear = 0.4;
usbc_w = 9.0;  usbc_h = 3.3;  usbc_sp = 17;
usba_w = 13.2; usba_h = 6.0;  usba_sp = 30;
hdmi_w = 15.2; hdmi_h = 5.8;  hdmi_sp = 28;
rj45_w = 16.0; rj45_h = 14.0; rj45_sp = 28;
db9_w = 16.7;  db9_h = 8.3;   db9_sp = 25;   // D-sub shell, sides slanted 10 deg
jack_d = 6.5;                                 // threaded 3.5 mm jack
sd_w = 27; sd_h = 3.2;                        // full-size SD extension holder slot
sd_bezel_w = 44; sd_bezel_h = 12; sd_bezel_depth = 1.5;   // Atari ST floppy look
sd_sp = 0;                                    // SD holder screw spacing: to measure (0 = none)
screw_d = 3.2;
port_z = 24;               // height of the port centres
label_size = 3.5; label_dz = -11; label_depth = 0.6;

// [label, wall, position along the wall (global X on the back wall, global Y on the sides), kind]
ports = [["HDMI", "back", 95, "hdmi"], ["LAN", "back", 145, "rj45"], ["FPGA", "back", 222, "usbc"],
         ["DEBUG", "back", 260, "usbc"], ["HUB", "back", 298, "usbc"],
         ["J0", "left", 217, "db9"], ["J1", "left", 262, "db9"],
         ["MOUSE", "right", 187, "usba"], ["WI-FI", "right", 227, "usba"],
         ["AUDIO", "right", 262, "jack"], ["SD", "right", 292, "sd"]];
