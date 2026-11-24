# KESTREL case: plan and measurement sheet

Goal (Matt, 9 Nov + 23 Nov 2026): a 3D-printed case for the VCF Montreal stand, the board and its
ports wired to the outside. One case for **both boards**: KESTREL (Z7-Lite 7010) and PEREGRINE
(the Z7-Lite 7020 variant, same PCB family: zeST builds for both with one XDC); to confirm on the
7020 when it arrives.

Method: a parametric **OpenSCAD** model (`kestrel_case.scad`, every dimension a named variable from the
sheet below), exported to STL per part; a printed **test fit** of the base plate + port wall first
(cheap, catches a wrong offset before the full print).

No mechanical drawing in the vendor files: `Z7-LITE_R11.pdf` is the schematic only (4 holes listed,
no positions). So the numbers below come from Matt's calliper.

## 1. Measurements needed (mm, calliper; photo of each side helps)

Origin: the PCB's bottom-left corner seen from the top, HDMI side = "back" (tell me if another side is better).

### Board (Z7-Lite)
| # | What | Value |
|---|---|---|
| B1 | PCB length x width x thickness | |
| B2 | 4 mounting holes: centre X,Y each + hole diameter | |
| B3 | tallest part on top (height above PCB) and where; heatsink/fan? | |
| B4 | tallest part underneath (pins, SD card sticking out) | |
| B5 | each connector: side, X offset of its centre, height of its centre above PCB, opening W x H: HDMI(s), USB host, USB-UART (serial console), SD slot (+ how far the card sticks out), power jack (or USB power), JTAG | |
| B6 | buttons (RST KEY, PS reset, user keys) and LEDs (power, DONE, user): X,Y | |

### Inside parts
| # | What | Value |
|---|---|---|
| H1 | the 6-port 9 V powered hub: L x W x H, port side(s), its power jack | |
| H2 | the Wi-Fi dongle on it (stick-out length) | |
| H3 | power: how the board is fed today (5 V jack? USB?) and the hub's 9 V: two supplies, or one 9-12 V in + a 5 V buck inside? | |
| H4 | anything else inside: the USB floppy?, the iCode adapter (or outside)?, a fan? | |

### What should reach the outside (tick and say which face)
- [ ] HDMI out
- [ ] SD card slot access (swap cards without opening)
- [ ] USB ports from the hub (how many on the front: keyboard, mouse, joysticks x2, floppy...)
- [ ] serial console (USB-UART) for the demo laptop
- [ ] power switch + power in
- [ ] reset button
- [ ] LEDs light pipes (power, activity)
- [ ] audio (PEREGRINE R88: USB dongle; KESTREL: an HDMI extractor box if needed)
- [ ] RJ45 later (EMIO Ethernet)

### Style
- Shape: flat box, ST-like wedge (keyboard-less), Falcon-style, or a "cartridge console"?
- Printer bed size (max part X x Y x Z) and material (PLA/PETG); colour.
- Logo/name on the lid (KESTREL; a PEREGRINE variant lid?), the falcon silhouette?
- Ventilation: the Zynq gets warm at 100 % LUT: slots over the FPGA, or a 30-40 mm fan?

## 2. Design (once the numbers are in)
- Base plate with standoffs on B2 (M2.5/M3 heat-set inserts), hub tray, cable channels.
- Port wall(s) cut from B5 with 0.5 mm clearance; SD slot slot-through with a finger notch.
- Lid with vents over B3, light pipes on B6, a reset push-rod.
- Split to fit the bed; screws, not glue (the board comes out for JTAG).
- Variant flag `board = "7010" | "7020"` if the 7020 PCB differs.

## 3. Matt's measurements and choices (23 Nov 2026)

Style: a **wedge with the keyboard on top**, after the RetroDeck (printables 220606, Raspberry Pi 3 +
MiSTer wedge) **made deeper**; other references looked at: printables 106485, 1431330, 106475, 964115.
Our model is drawn from scratch from these measurements (inspiration only, nothing copied).

### Parts inside (mm, confirmed by Matt)
| Part | L x W x H | Notes |
|---|---|---|
| MicroPhase Z7-Lite (FPGA) | 80 x 60 (credit-card size), PCB ~2; 4 corner holes, hole edge 1 mm from both sides (centre = 1 + d/2; d to confirm, 3.2 assumed -> centres 2.6, 2.6) | tallest part = its RJ45 jack (~13-14 typical, to measure) + PCB; budget ~20 above the standoffs |
| E-YOOSO Z-66 keyboard (USB, gaming, no numpad) | W 355 x D 125 x H 10 (+ keycaps) | low-profile TKL, 87 keys (US), blue switches, 740 g, spec width ~360 (tray sized 362 inside), aluminium-look frame, RGB, flip-out feet (folded in the tray), DETACHABLE USB-C cable (port position: to confirm); product photo szaosd.com, manual manuals.plus/asin/B095KGQ4PJ | RESTS ON the top of the wedge (not built in), like the RetroDeck photo (printables 220606 image 3672); |
| iCode (USB to DB9 joysticks) | 90 x 40 x 20 | |
| mini powered USB hub, 6 ports, USB-C 9 V in, USB2 | 75 x 40 x 10 | cables leave on ALL 4 sides: keep clearance |

### Panel connectors (male/female extensions, case side <- inside)
| Case connector | Goes to |
|---|---|
| USB-C | FPGA board power |
| USB-C | FPGA board debug (USB-UART serial console) |
| USB-A | hub: mouse |
| USB-A | hub: Wi-Fi dongle (outside: better antenna) |
| USB-A | hub: the LaCie Pocket USB floppy drive (706018 / MyFloppy3, 140 x 45 x 16), used OUTSIDE the case |
| DB9 | iCode: joystick 0 |
| DB9 | iCode: joystick 1 |
| 3.5 mm jack | a USB sound card on the hub (PEREGRINE R88: KESTREL has no USB audio path) |
| HDMI | FPGA board |
| RJ45 | FPGA board (Ethernet, EMIO, later) |
| SD card extension | FPGA board's SD slot |

Inside: keyboard -> hub, iCode -> hub, hub upstream -> the board's USB host; hub ports: keyboard, iCode,
mouse, Wi-Fi, sound card, floppy (external, via its case USB-A) = 6 of 6 (no spare port).

### Z7-Lite layout (from the product photo, top view, long edges = 80 mm)
- LEFT short edge: USB-C "UART" (top) and USB-C "JTAG" (below): the debug cable and, presumably, the power one
  (to confirm which USB-C powers the board); 4 push buttons K1-K4 and the LEDs near the bottom-left.
- RIGHT short edge: USB-A host (top, -> the hub), RJ45 "ETH" (middle, the tallest part), HDMI TX (bottom).
- LONG edges: two 2x20 GPIO headers (GPIO2 top, GPIO1 bottom): keep clearance above them (free pins:
  the I2S DAC option of R88 would plug here).
- SD card slot: UNDERNEATH, under the 4 buttons (left edge, Matt): the SD extension plugs in from the left, below the board -> standoffs >= 8 mm so the extension plug clears the base.
- 4 corner holes.
So the board sits with its right edge facing the back panel (HDMI + RJ45 extensions short) and its
left edge reachable for the two USB-C extensions.

### Extension cables (Matt, 23 Nov)
Board -> case: one male/female extender per port: RJ45, 2x USB-C, 1x USB2 (USB-A), HDMI, SD card.
They are SEMI-RIGID (hard to bend): the layout must give them room: straight runs from the board's
edge to the panel where possible, large bend radii, no tight U-turns. Needed: each one's length, its
minimum bend radius, and how its female end mounts (screw ears + spacing, or a clip/glue).

### The reference case's STLs (prototypes/kestrel_case/*.STL: a MiSTer wedge, NOT ours: never committed)
Six parts, printed lying, measured from the meshes (mm):
| Part | depth x half-width x height |
|---|---|
| front left / front right (keyboard tray) | 157 x 186.5 x 49 |
| back left / back right (electronics, port cut-outs in the back wall) | 120 x 186.5 x 49 |
| top left / top right (covers over the back, vent slots) | 133.5 x 186.5 x 5 |
So the whole case is 373 wide (2 x 186.5) x ~277 deep x 49 high, split in the middle; every part fits a
~190 x 160 mm bed. Matt: the back (120) is too shallow for the semi-rigid extenders. Ours keeps the same
6-part split and heights but a deeper back section, set from the extenders' lengths and bend radii.

### Power and USB-C (Matt, 23 Nov)
Three USB-C panel ports, two power supplies:
| Case USB-C | Inside to | Notes |
|---|---|---|
| DEBUG | the board's UART USB-C | the serial console (the lead's line to the board) |
| FPGA POWER | the board's JTAG USB-C | supply 1 |
| HUB POWER | the hub's USB-C power input (9 V) | supply 2; a 3rd USB-C extender to buy |
Label the three on the panel (DEBUG / FPGA / HUB) so a 9 V supply never goes into the board's port.
Schematic check (Z7-LITE_R11.pdf p.14): both USB-C ports power the board: VCC_USB2UART_5V and
VCC_USB2JTAG_5V each go through an SS24 Schottky diode (D8, D9) into VCC_5V, behind a 2 A fuse (F2). So the
power supply on JTAG and the laptop on UART at the same time is safe (diode-OR, no back-feed between them);
whichever is higher (minus ~0.4 V) feeds the board. The GPIO headers also carry VCC_5V.

### Extender lengths (Matt, 23 Nov; plug to plug, cm)
| Extender | Length | Count |
|---|---|---|
| USB2 (USB-A) | 55 | mouse, Wi-Fi, (board USB-A -> hub?) |
| USB-C | 31 | 3 (DEBUG, FPGA, HUB) |
| HDMI | 31 | 1 |
| RJ45 | 31 | 1 |
| DB9 | 32 | 2 (joysticks, from the iCode) |
| SD card (full-size SD holder at the panel) | 20 | 1 |
| USB audio (jack) | 28 | 1 |
These are much longer than the straight runs (board edge to panel ~3-10 cm), so each semi-rigid cable
needs a SLACK LOOP inside: plan cable channels/loop bays along the walls (one big U per cable, radius >=
the cable's minimum bend), and clips to hold the loops. That, not the board, sets the back's depth.
Bend (Matt): about a 6 cm wide U (inner radius ~30 mm). A 31 cm cable with a ~10 cm direct run keeps ~21 cm
of slack = one U with ~6 cm legs (2 x 60 + pi x 30 ~ 21 cm): a ~60 x 90 mm footprint per loop, or one
shared bay where same-direction cables loop together (they stack: 49 mm of height). First estimate: back
section ~170 deep instead of 120 (case ~327 deep in all); the top-view layout will settle it.

### Panel mounting (female ends, 2 screw holes, centre to centre; Matt)
| Female end | Screw spacing |
|---|---|
| USB-C | 17 mm |
| USB2 (USB-A) | 30 mm |
| HDMI | 28 mm |
| RJ45 | 28 mm |
| DB9 | 25 mm (D-sub standard, confirmed) |
| SD holder, audio jack | to measure (jack: threaded nut?) |
Cut-out sizes: measured from the female shell (W x H) at fit-test time; the model uses each connector's
standard opening + 0.4 mm clearance meanwhile.
SD holder on the RIGHT side, where an Atari ST has its floppy drive (Matt: "replace the floppy disk"):
style it like the ST's drive slot (a recessed slot + an eject-notch look).

## 4. The joint to the reference front parts (measured 23 Nov 2026, `tools/joint_analysis.py`)

Method: slice the STLs (read only, never copied) at planes near each mating face with numpy-stl, cluster the
cut segments into loops, report round loops (holes) and bosses. The parts lie as printed: x = depth (the back
part's joint face is x = 120.83, the front part's is x = 1.2; the front tip is x = 158.2), y = width
(0.85 .. 187.35), z = height 0 .. 49. LEFT parts: the OUTER side is y = 0.85, the CENTRE is y = 187.35
(RIGHT parts: mirrored).
`uv run --with numpy-stl --with numpy python fpga/case/tools/joint_analysis.py <dir> "front left.STL" backleft-mister.STL --slice 0 1.5`

| Interface | Numbers (mm) | Where measured |
|---|---|---|
| Front <-> back joint face | flat, NO lip or tongue: the section at x = 1.3 / 120.7 is the plain 186.5 x 49 outline | front x = 1.3..6, back x = 119..120.7 |
| Joint holes | 2 per half, round **d 3.15**, axis along x, centre **z = 39**, at y = 11.85 and 182.35 = **11.0 from the outer side and 5.0 from the centre face**; same on front and back, so they line up | both faces |
| Joint hole depth | ~10 each side (present at x = 8, gone at x = 12 on the front; present at x = 113, gone at 110 on the back): blind holes in both faces, no nut trap found | slices x = 1.3..30 and 120.7..100 |
| Hole bosses | 10 mm round bosses around the holes (z 36..42, y 182.35), ribs behind them on the front | z = 36/39/42 slices |
| Centre joint (left <-> right back halves) | holes **d 3.15, axis along y, z = 29**, at x = 12.32 and 115.82 (11.5 from the back wall's outside, 5.0 from the joint face), ~9-10 deep from the centre face; the outer face (y = 0.85) has none | slices y = 168..186.9 |
| Front parts' centre holes | d 3.15 at x = 15.19 (z 14) and 117.76 (z 7.5) along y | y = 186.9 |
| Cover fixing | 4 posts per half, **pilot d 2.75** (self-tapping M3) in the top (z = 49), ~10 deep, at (x, y) = (7.3, 7.35), (115.8, 5.84), (7.3, 182.35), (115.8, 182.35): 7 from the back wall's outside, 5 from the joint face, 5-7 from the sides; the cover: d 2.75 holes with a **d 6 counterbore** at the same spots | back z = 46..48.5; cover z = 0.5 / 2.5 |
| Cover size | 133.5 deep: the 120 back + ~13.5 over the front part; 4-5 thick | top bbox |
| Reference back wall | window-like wall at x = 0.8..4.5 and a bulkhead at x ~ 6 with port holes d 3.15 at z = 26.74 (y = 18.44 and 50.93 = 32.5 apart) | x = 1.5..6 (not reproduced: our wall is our own) |

Reproduced in our back parts (`lib/params_ports.scad`, group "Joint"): the same two d 3.15 x 10 blind holes in
the joint face (z 39, 11.0 / 5.0 from the sides; the outer one in a 13 x 10 block fused to the side wall, the
inner one in the corner post), the same open joint face, the same cover pilots (d 2.75 x 10) and counterbored
cover holes. The centre joint holes (d 3.15, z 29) are cut at 4 positions along the 170 depth (the reference's
two are at 5 and 11.5 from the ends). The mesh shows no nut trap: how a screw bites is NOT visible (d 3.15 on both
sides suggests M3 screws into a printed thread, a threaded stud or dowel pins): settle it by looking at the
printed front parts.

## 5. Model v1 (23 Nov 2026)

Done: `kestrel_case.scad` + `lib/*.scad` (each under 100 lines): every dimension a Customizer variable
(`lib/params_ports.scad`: groups Case, Joint, Cover, Board, Loops, Ports); `part = "all"` (assembly) |
`back_left` | `back_right` | `top_left` | `top_right`; assembly ghosts (board 80 x 60 with the 14 mm RJ45, hub,
iCode, keyboard on the wedge slope, the two reference front STLs as `%import` ghosts, read from
`prototypes/kestrel_case/` for the view only; a missing file is a warning). Checked by `tools/check_stl.py`:

| Part | Size (mm) | Bed 190 x 180 | Manifold |
|---|---|---|---|
| back_left / back_right | 186.5 x 170.0 x 49 | fits | yes (OpenSCAD "Simple: yes", 0 open edges) |
| top_left / top_right | 186.5 x 176.0 x 4 | fits (176 of 180) | yes |

No part crosses the left | right split (x = 186.5).

Features: walls 3, floor 3, height 49, open top and open joint face (the cables go on into the tray); back-wall
and side-wall cut-outs for the 11 ports at the layout's positions with the 2 screw holes at the given spacings
(USB-C 17, USB-A 30, HDMI 28, RJ45 28, DB9 25 standard D shape; jack d 6.5; the SD slot 27 x 3.2 with a recessed
bezel, an eject-button recess and a finger notch, ST-floppy style, on the right wall); labels engraved 0.6 deep
outside (FPGA, DEBUG, HUB, HDMI, LAN, J0, J1, MOUSE, WI-FI, AUDIO, SD); 4 standoffs 8 tall (d 7, M3 insert hole d 4.2
x 6) 2.6 mm from the board corners; corner-clip trays for the hub (75 x 40, open on all 4 sides) and the iCode
(90 x 40) with zip-tie slots; 5 semicircular loop guides (inner radius 30, the cable runs round the OUTSIDE, 4 mm
lip); 11 vent slots in the left cover over the board; "KESTREL" engraved 1.2 deep on the left cover; 5 cover
screws per half.

Changes against `layout_topview.py` (a sketch): its loops overlapped each other and ran through the back wall,
so the centres moved: HDMI/RJ45 (70,270) -> (85,292), USB2 (340,300) -> (335,292), DB9 (60,250) -> (45,245),
SD/jack (330,185) -> (325,185); the model also clamps every guide inside the walls (the USB2 and HDMI loops end
at y = 289 rather than 292).

ASSUMED, to test-fit:
- the joint hole depth and the screw type (section 4); the front part's own rib bosses are not modelled;
- cut-out sizes (standard shell + 0.4 mm): measure each female shell; port height 24 for every port; the SD
  holder's real W x H and screw spacing (`sd_sp = 0`: no holes yet) and the jack's nut;
- the board's hole d (3.2), edge (2.6), RJ45 height (14); its back edge (the 60 wide short edge) faces the back
  wall, ~29 mm from it; PEREGRINE (7020) assumed identical;
- the cover sits ON the 49 high walls (53 at the back) and overlaps the front part by 6 mm (the reference's 13.5
  would make a 183.5 deep part, too long for the bed): how it meets the wedge top is untested;
- 5 cover screws per half (no outer middle post: it would meet the WI-FI holes); a 4 mm plate may flex;
- the cable loops' real bend radius and the stacking (3 USB-C x 31 cm in one guide: ring 26 high);
- the two halves' 3 mm centre walls make a 6 mm double wall, screwed at 4 centre holes.

Printing order: 1) a back-wall test strip: `openscad -D 'back_d=14' -D 'part="back_right"' -o strip.stl
kestrel_case.scad` is a 14 deep slice of the tub with the full port wall (and a short sidewall): fit the real
extenders, shells and the SD holder, fix the cut-outs; 2) the two covers (fast; check the posts against the
front parts); 3) back_left; 4) back_right (more ports). The reference's front parts: printed as is.

## 6. Lead review of model v1 (23 Nov, night)
- Renders checked (assembly, top, back): ports on the agreed walls, labels DEBUG/FPGA/HUB/LAN/HDMI
  readable, board/hub/iCode ghosts placed, no part crosses the split, all 4 STLs manifold.
- FOR MATT (morning):
  1. **Your printer's bed size**: the model assumed 190 x 180 (my guess, never measured). The reference
     cover overlaps the front part by 13.5 mm; ours only by 6 so it fits 176 deep. If the bed is >= 185
     deep (most are 220-256), set `cover_overlap = 13.5` like the reference, otherwise a ~7 mm strip over the
     front part's top edge may stay open: check on the printed front part where the reference cover ends.
  2. **How the front/back joint is screwed** (both faces have blind d 3.15 holes: printed thread, threaded
     studs, or dowels + glue?): look at your printed front part.
  3. Print the back-wall test strip first (README) with the real extenders in hand.
- Loop guides are full-height half cylinders: heavy on filament; v2 can make them 15 mm tall clips.
