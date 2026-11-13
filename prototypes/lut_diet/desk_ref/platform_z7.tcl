
# Create Project

create_project -force -name platform_z7 -part xc7z010clg400-1
set_msg_config -id {Common 17-55} -new_severity {Warning}
set_param general.maxThreads 2

# Add project commands


# Add Sources

read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/blitter/zm_blit.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/blitter/zm_blit_blit.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/blitter/zm_blit_chk.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/blitter/zm_blit_clip.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/blitter/zm_blit_core.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/blitter/zm_blit_htbit.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/blitter/zm_blit_line.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/blitter/zm_blit_px.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/blitter/zm_blit_pxq.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/blitter/zm_blit_q.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/blitter/zm_blit_rdmux.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/blitter/zm_blit_regs.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/blitter/zm_blit_row.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/blitter/zm_blit_tex.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/blitter/zm_blit_tfetch.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/blitter/zm_blit_tri.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/blitter/zm_blit_twalk.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/glass/zm_glass_regs.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/glass/zm_glass_ptr.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/glass/zm_glass_osd.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_dvi_out.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_hdmi_out.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_tmds_enc.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_tmds_shift.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_video_bg.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_video_comp.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_video_copchk.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_video_copper.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_video_dcram.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_video_desk.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_video_fetch.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_video_latch.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_video_mix.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_video_out.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_video_paint.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_video_palwb.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_video_pass.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_video_plane.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_video_planepath.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_video_regs.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_video_rowio.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_video_scan.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_video_scanfetch.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_video_sdpram.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_video_sync.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_video_tcfade.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video/zm_vtiming.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/audio/zm_audio_frac.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/audio/zm_audio_ym.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/audio/zm_audio_pokey.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/audio/zm_audio_pcm.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/audio/zm_audio_mix.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/audio/zm_audio_core.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/audio/zm_audio_sched.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/audio/zm_audio_soc.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/audio/zm_audio_fifo.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/audio/zm_pokey.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/audio/zm_pokey_pair.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/audio/zm_pokey_poly.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/third_party/jt49/hdl/jt49.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/third_party/jt49/hdl/jt49_cen.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/third_party/jt49/hdl/jt49_div.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/third_party/jt49/hdl/jt49_eg.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/third_party/jt49/hdl/jt49_exp.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/third_party/jt49/hdl/jt49_noise.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/build/vexgen/VexRiscv_SndNdD16Dyn8Sx.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/sim/zm_snd_putc.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/hdmi/zm_hdmi_acr.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/hdmi/zm_hdmi_island.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/hdmi/zm_hdmi_packets.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/hdmi/zm_hdmi_enc.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/hdmi/zm_hdmi_tx.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/build/vexgen/VexRiscv_I16w2D16w2SealFpuZmxE.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/seal/zm_seal.v}
read_verilog {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/build/board_desk_bars/gateware/platform_z7.v}

# Add EDIFs


# Add IPs


# Add constraints

read_xdc platform_z7.xdc
set_property PROCESSING_ORDER EARLY [get_files platform_z7.xdc]

# Add pre-synthesis commands


# Synthesis

synth_design -directive AreaOptimized_high -top platform_z7 -part xc7z010clg400-1 -include_dirs {/home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/gen /home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/gen /home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/video /home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/gen /home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/blitter /home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/rtl/seal}

# Synthesis report

report_timing_summary -file platform_z7_timing_synth.rpt
report_utilization -hierarchical -file platform_z7_utilization_hierarchical_synth.rpt
report_utilization -file platform_z7_utilization_synth.rpt
write_checkpoint -force platform_z7_synth.dcp

# Add pre-optimize commands


# Optimize design

opt_design -directive ExploreArea

# Add pre-placement commands

set_max_delay -datapath_only -from [get_clocks -of_objects [get_pins -of_objects [get_cells -hier -filter {REF_NAME == PLLE2_ADV}] -filter "REF_PIN_NAME == CLKOUT0"]] -to [get_clocks -of_objects [get_pins -of_objects [get_cells -hier -filter {REF_NAME == PLLE2_ADV}] -filter "REF_PIN_NAME == CLKOUT2"]] 25.000
set_max_delay -datapath_only -from [get_clocks -of_objects [get_pins -of_objects [get_cells -hier -filter {REF_NAME == PLLE2_ADV}] -filter "REF_PIN_NAME == CLKOUT2"]] -to [get_clocks -of_objects [get_pins -of_objects [get_cells -hier -filter {REF_NAME == PLLE2_ADV}] -filter "REF_PIN_NAME == CLKOUT0"]] 10.000
set_max_delay -datapath_only -from [get_clocks -of_objects [get_pins -of_objects [get_cells -hier -filter {REF_NAME == PLLE2_ADV}] -filter "REF_PIN_NAME == CLKOUT1"]] -to [get_clocks -of_objects [get_pins -of_objects [get_cells -hier -filter {REF_NAME == PLLE2_ADV}] -filter "REF_PIN_NAME == CLKOUT2"]] 25.000
set_max_delay -datapath_only -from [get_clocks -of_objects [get_pins -of_objects [get_cells -hier -filter {REF_NAME == PLLE2_ADV}] -filter "REF_PIN_NAME == CLKOUT2"]] -to [get_clocks -of_objects [get_pins -of_objects [get_cells -hier -filter {REF_NAME == PLLE2_ADV}] -filter "REF_PIN_NAME == CLKOUT1"]] 8.000
set_max_delay -datapath_only -from [get_clocks -of_objects [get_pins -of_objects [get_cells -hier -filter {REF_NAME == PLLE2_ADV}] -filter "REF_PIN_NAME == CLKOUT0"]] -to [get_clocks -of_objects [get_pins -of_objects [get_cells -hier -filter {REF_NAME == PLLE2_ADV}] -filter "REF_PIN_NAME == CLKOUT1"]] 8.000
set_max_delay -datapath_only -from [get_clocks -of_objects [get_pins -of_objects [get_cells -hier -filter {REF_NAME == PLLE2_ADV}] -filter "REF_PIN_NAME == CLKOUT1"]] -to [get_clocks -of_objects [get_pins -of_objects [get_cells -hier -filter {REF_NAME == PLLE2_ADV}] -filter "REF_PIN_NAME == CLKOUT0"]] 10.000
opt_design -control_set_merge -merge_equivalent_drivers

# Placement

place_design -directive ExtraTimingOpt
phys_opt_design -directive AggressiveExplore

# Placement report

report_utilization -hierarchical -file platform_z7_utilization_hierarchical_place.rpt
report_utilization -file platform_z7_utilization_place.rpt
report_io -file platform_z7_io.rpt
report_control_sets -verbose -file platform_z7_control_sets.rpt
report_clock_utilization -file platform_z7_clock_utilization.rpt
write_checkpoint -force platform_z7_place.dcp

# Add pre-routing commands


# Routing

route_design -directive AggressiveExplore
phys_opt_design -directive AggressiveExplore
write_checkpoint -force platform_z7_route.dcp

# Routing report

report_timing_summary -no_header -no_detailed_paths
report_route_status -file platform_z7_route_status.rpt
report_drc -file platform_z7_drc.rpt
report_timing_summary -datasheet -max_paths 10 -file platform_z7_timing.rpt
report_power -file platform_z7_power.rpt

# Bitstream generation

write_bitstream -force platform_z7.bit 

# End

quit