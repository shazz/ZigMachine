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
| MicroPhase Z7-Lite (FPGA) | 80 x 60 x 2 | 2 = PCB; tallest part to measure |
| E-YOOSO Z-66 keyboard (USB, gaming, no numpad) | 355 x 25 x 1 (+ keys) | RESTS ON the top of the wedge (not built in), like the RetroDeck photo (printables 220606 image 3672); depth to confirm |
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
