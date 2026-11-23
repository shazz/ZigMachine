# PEREGRINE: MicroPhase Z7 with an XC7Z020 (CLG400). UNVERIFIED until the board is here: the part's
# speed grade and the vendor's board.xdc (no XDC is seeded from the 7010's: a build stops at
# BoardXdcMissingError until the real one is copied in, README.md).
BOARD_PART := xc7z020clg400-1
BOARD_DBPART := xc7z020clg400
BOARD_CHIP := xc7z020
# Same SoC as KESTREL until B2 gives PEREGRINE its own parameters (soc/boards.py).
BOARD_CPU_CORE := build/vexgen/VexRiscv_I16w2D16w2SealFpuZmxE.v
BOARD_SOUND_CORE := build/vexgen/VexRiscv_SndNdD16Dyn8Sx.v
BOARD_SOC_FLAGS := --blit --sound-cpu --posted 8 --no-read-bypass --ziggy-reads prefetch \
	--cpu-netlist $(BOARD_CPU_CORE) --sound-core $(BOARD_SOUND_CORE) --vivado-directives fit_timing
