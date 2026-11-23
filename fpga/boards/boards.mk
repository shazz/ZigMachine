# BOARD=kestrel|peregrine (repo reorg Part B1, prototypes/repo_reorg/PLAN.md). Included by the Makefile.
# soc/boards.py is the same table for Python (tests/test_boards.py keeps the two in step); an unknown
# board stops here, never a silent default. Default: kestrel, so every older command builds what it did.
BOARD ?= kestrel
BOARD_DIR_kestrel   := boards/microphase_z7_7010
BOARD_DIR_peregrine := boards/microphase_z7_7020
BOARD_DIR := $(BOARD_DIR_$(BOARD))
ifeq ($(BOARD_DIR),)
$(error BOARD=$(BOARD) is not a board: kestrel or peregrine (fpga/boards/boards.mk))
endif
include $(BOARD_DIR)/board.mk
BOARD_XDC := $(BOARD_DIR)/board.xdc
# What the board's builds write: the SoC (soc_z7) and the release bitstream (release/).
BOARD_BUILD := build/$(BOARD)
SOC_OUT     := $(BOARD_BUILD)/soc_z7
# Every tool the Makefile runs (soc.*, tools/openxc7.sh, tools/vivado_*.sh) builds for this board.
export ZM_BOARD := $(BOARD)
export ZM_PART := $(BOARD_PART)
export ZM_DBPART := $(BOARD_DBPART)
export ZM_CHIP := $(BOARD_CHIP)
