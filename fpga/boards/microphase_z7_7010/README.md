# MicroPhase Z7, XC7Z010-1CLG400

Drop two files from the **vendor's board package** here. Neither can be derived
or guessed safely, and `soc/platform_z7.py` refuses to build without the first:

| File | From | Used for |
|---|---|---|
| `board.xdc` | the board package's constraint file | every PL pin: the oscillator, HDMI or PMOD, LEDs, buttons. Read by `soc/platform_z7.py`, so no pin number is typed anywhere else. |
| `ps7_init.c` / `ps7_init.h` (or the `.tcl`) | the board package's Vivado project (the hardware handoff) | the ARM side: DDR3 timings, PS clocks, MIO muxing. U-Boot SPL uses it, so the ARM can boot without Vivado's FSBL. |

Then check these against the schematic and pass them to the SoC:

- **The PL oscillator:** its XDC port name (`--osc`) and frequency (`--osc-hz`, default 50 MHz).
- **The DDR size:** typically 512 MB. Only the 7 MiB machine window is mapped to the PL.
- **The video connector:** HDMI or a PMOD. If it is HDMI, which pins are the TMDS pairs.
