# PEREGRINE: MicroPhase Z7-Lite with an XC7Z020-1CLG400C (the vendor manual: the same PCB as the 7010).
# board.xdc is KESTREL's, every ball checked on both chips (tools/board_xdc.py derive kestrel peregrine,
# run by tools/fetch_board.sh peregrine; README.md). Without it a build stops at BoardXdcMissingError.
BOARD_PART := xc7z020clg400-1
BOARD_DBPART := xc7z020clg400
BOARD_CHIP := xc7z020
# The release SoC: soc/boards.py Board.soc, KESTREL's to start with; its two netlists (tests/test_boards.py):
BOARD_CPU_CORE := build/vexgen/VexRiscv_I16w2D16w2SealFpuZmxE.v
BOARD_SOUND_CORE := build/vexgen/VexRiscv_SndNdD16Dyn8Sx.v
