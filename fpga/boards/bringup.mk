# Day 1 on a new board: the bring-up bitstreams with VIVADO, for a board openXC7 has no chipdb for yet
# (PEREGRINE). Included by the Makefile after flow.mk; boards/microphase_z7_7020/README.md "Day 1".
#   make BOARD=peregrine bringup   -> build/<board>/bringup/<top>/<top>.bit, one Vivado at a time:
#     blink_top      the LEDs blink off the 50 MHz PL oscillator (the PL is alive, the XDC's clock and LEDs)
#     hdmi_test_top  the 800x600@60 test pattern on HDMI1 (the TMDS pins, the PLL)
#     osd_test_top   the glass OSD over the pattern, its registers on GP0 at 0x43C0_0000 (the PS-PL path)
# The tops are the openXC7 bring-up's (make blink / hdmi-test / osd-test), unchanged; only the tool differs.
BRINGUP := $(BOARD_BUILD)/bringup

define bringup_rule
$(BRINGUP)/$(1)/$(1).bit: $(2) $(BOARD_XDC) gen/memmap.vh gen/glass_map.vh gen/glass_font.vh
	@mkdir -p $$(@D)
	tools/openxc7.sh xdc $(BOARD_XDC) rtl/board/$(1).v > $$(@D)/$(1).xdc
	echo 'create_clock -period 20.000 [get_ports PL_CLK_50M]' >> $$(@D)/$(1).xdc
	$(VIVADO_LOCK) tools/vivado_bit.sh $(1) $$(abspath $$(@D)) $$(abspath $$(@D))/$(1).xdc "" $$(abspath $(2))
endef

$(eval $(call bringup_rule,blink_top,rtl/board/blink_top.v))
$(eval $(call bringup_rule,hdmi_test_top,$(HDMI_TEST_V)))
$(eval $(call bringup_rule,osd_test_top,$(OSD_TEST_V)))

.PHONY: bringup
bringup: $(foreach t,blink_top hdmi_test_top osd_test_top,$(BRINGUP)/$(t)/$(t).bit)
