# KESTREL: MicroPhase Z7-Lite, XC7Z010-1CLG400 (README.md here; board.xdc from tools/fetch_board.sh).
BOARD_PART := xc7z010clg400-1
BOARD_DBPART := xc7z010clg400
BOARD_CHIP := xc7z010
# The release bitstream's SoC (the board's since KESTREL v1.3, 2026-11-20, lut_diet bit_a):
# ZIGGY with the f32 FPU + ZM-X, BARD SndNdD16Dyn8Sx, CHISEL, the sound CPU, posted stores.
BOARD_CPU_CORE := build/vexgen/VexRiscv_I16w2D16w2SealFpuZmxE.v
BOARD_SOUND_CORE := build/vexgen/VexRiscv_SndNdD16Dyn8Sx.v
BOARD_SOC_FLAGS := --blit --sound-cpu --posted 8 --no-read-bypass --ziggy-reads prefetch \
	--cpu-netlist $(BOARD_CPU_CORE) --sound-core $(BOARD_SOUND_CORE) --vivado-directives fit_timing
