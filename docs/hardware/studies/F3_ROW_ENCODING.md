# F3: a narrower row encoding for FRESCO? (study, 2026-10-24)

**Decision: not now (2026-10-24, lead): only 24-bit packed is exact, ~0.03 Mc a frame for 150-250 LUT at 89 %.**

SOC_REVIEW.md F3 proposed RGB565 rows to halve the compositor's DDR traffic. This is the study the lead
asked for after 3a/3b (FRESCO_OPTIONS.md): which encodings stay pixel-exact, what each saves on the
board as it is now, what it costs, and whether to build one. Study only: no RTL.

## What a row is today

| row | bytes | beats | read by | written by |
|---|---|---|---|---|
| PFB row (RGBA, the machine's own) | 3,200 | 400 | a plane-major pass that is not its line's first | a pass whose line has a later plane-major layer (never the top layer: `nopfb`, 3a) |
| picture row ({0,B,G,R}) | 3,200 | 400 | a later layer's pass (plane-major), the scanout (every line, 60 Hz) | the top layer of every line, every frame |

Since line-major groups (2026-10-18), `nopfb` and 3a's pure-handler groups, most frames move a line's
rows once: one picture store a line, PFB rarely. What is left per frame (board, VCAL: a row store
~387 sys, a load ~422): 280 picture stores = **~0.11 Mc**, plus loads only where a stack stays
plane-major (an impure handler plane between others). The scanout reads 896 KB a frame (54 MB/s),
outside ZIGGY's budget.

## Survey: which colours the pictures hold (one frame per corpus cart, build/vdump)

| cart | picture off the 565 grid | off 666 | PFB alpha values (partial %) |
|---|---|---|---|
| leonard | 100 % | 57 % | 2 (0 %) |
| medium_overscan | 98 % | 42 % | 2 |
| tcb_colorshock | 90 % | 82 % | 1 |
| badflicker | 88 % | 75 % | 1 |
| res_switch / scroll / tutorial | 52-57 % | 45-57 % | 1 |
| maxi / union_intro / gen4_3615 | 9-18 % | 9-18 % | 2-6 (union_intro 0.3 % partial) |
| ancool | 0.4 % | 0.3 % | 22 (0.1 % partial) |
| replicants, fallen_angels, dhs_0pxl0reg | 0 % | 0 % | 1-2 |

CODEF ports and the browser's blending put arbitrary 24-bit colours on screen; ST-legal (3-4 bits a
channel) carts are the minority. Alpha is 0/255 almost everywhere, but not everywhere (ancool's stars,
union_intro's partial-alpha palette entries).

## Encodings

| encoding | exact? | picture beats | saving a frame (store only) | cost |
|---|---|---|---|---|
| RGB565 picture | **no** (above) | 200 | ~0.05 Mc | - |
| RGB666 (18-bit) picture | **no** | 225 | ~0.05 Mc | - |
| RGB565 + per-pixel exception | yes | variable | < 0.05 Mc | a variable-length row: the scanout's fixed-deadline fetch and the mixer's random access both break |
| 24-bit packed picture (no pad byte) | **yes** | 300 | **~0.027 Mc** (25 % of the stores), scanout 54 -> 40 MB/s | a 3-byte <-> 8-byte lane packer in rowio's store and load paths and in the scanout fetch (pixel clock), the accumulator kept 24-bit (it already is: 48 bits a pair); est. +150-250 LUT |
| PFB RGB565 + alpha plane | no (RGB off-grid) | - | - | - |
| PFB 24-bit + 1-bit alpha | no (partial alpha exists) | - | - | - |

## Recommendation

**Do not build F3 now.** The only exact encoding (24-bit packed pictures) saves ~0.03 Mc a frame
(~2 % of a 60 Hz frame) and some scanout bandwidth that is not short (54 MB/s of a 2 GB/s DDR), for
~200 LUT on a build that just closed at 89 % LUT with directive tuning (copper_stage: sys +0.068 ns).
The bandwidth case F3 was written for (11.7 MB a frame at 3 planes, before line-major) no longer
exists: rows move once a line now.

Where FRESCO's time goes now (FRESCO_OPTIONS.md A): a pass's fixed ~171 comp clocks, fill / paint /
mix ~400 clocks each, and one row store. The levers left, in order: (1) the dirty-line plan paying on
more carts (vadapt keeps it OFF where comparing a redrawn plane costs more than the border lines save:
a "covered lines always new" rule for such planes would skip borders for free, as handler planes do);
(2) LUT room first (the blitter's `chk`/`htb`/`tri` fold, SOC_REVIEW F5), then (3) 24-bit pictures if
the scanout's bandwidth ever matters (more planes, a higher resolution).

F2 (scanout underrun): the probe's sticky underrun flag reads `boot` on every cart measured since
10-23 (an underrun before the first frame, the boot sequence's) and never during a run; a per-frame
counter is cheap (one CSR) but has no failure to explain yet.
