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
