# KESTREL: MicroPhase Z7-Lite, XC7Z010-1CLG400 (README.md here; board.xdc from tools/fetch_board.sh).
BOARD_PART := xc7z010clg400-1
BOARD_DBPART := xc7z010clg400
BOARD_CHIP := xc7z010
# The release SoC is soc/boards.py Board.soc (soc/board_soc.py KESTREL_V13); make needs its two netlists
# as prerequisites, so they are named here too (tests/test_boards.py keeps the two in step):
# ZIGGY with the f32 FPU + ZM-X, BARD SndNdD16Dyn8Sx.
BOARD_CPU_CORE := build/vexgen/VexRiscv_I16w2D16w2SealFpuZmxE.v
BOARD_SOUND_CORE := build/vexgen/VexRiscv_SndNdD16Dyn8Sx.v
