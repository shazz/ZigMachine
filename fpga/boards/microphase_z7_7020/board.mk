# PEREGRINE: MicroPhase Z7-Lite with an XC7Z020-1CLG400C (the vendor manual: the same PCB as the 7010).
# board.xdc is KESTREL's, every ball checked on both chips (tools/board_xdc.py derive kestrel peregrine,
# run by tools/fetch_board.sh peregrine; README.md). Without it a build stops at BoardXdcMissingError.
BOARD_PART := xc7z020clg400-1
BOARD_DBPART := xc7z020clg400
BOARD_CHIP := xc7z020
# Same SoC as KESTREL until B2 gives PEREGRINE its own parameters (soc/boards.py).
BOARD_CPU_CORE := build/vexgen/VexRiscv_I16w2D16w2SealFpuZmxE.v
BOARD_SOUND_CORE := build/vexgen/VexRiscv_SndNdD16Dyn8Sx.v
BOARD_SOC_FLAGS := --blit --sound-cpu --posted 8 --no-read-bypass --ziggy-reads prefetch \
	--cpu-netlist $(BOARD_CPU_CORE) --sound-core $(BOARD_SOUND_CORE) --vivado-directives fit_timing
