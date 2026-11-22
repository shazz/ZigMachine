set files {
  /home/matt/projects/ZigMachine/fpga/rtl/blitter/zm_blit_px.v
  /home/matt/projects/ZigMachine/fpga/rtl/blitter/zm_blit_pxq.v
}
read_verilog $files
set_property include_dirs {/home/matt/projects/ZigMachine/fpga/gen /home/matt/projects/ZigMachine/fpga/rtl/video /home/matt/projects/ZigMachine/fpga/rtl/blitter /home/matt/projects/ZigMachine/fpga/rtl/audio /home/matt/projects/ZigMachine/fpga/third_party/jt49/hdl} [current_fileset]
synth_design -top zm_blit_px -part xc7z010clg400-1 -mode out_of_context
opt_design -directive Explore
create_clock -period 10.0 -name clk_ooc [get_ports clk]
place_design -directive ExtraTimingOpt
route_design -directive MoreGlobalIterations
report_timing_summary -file /tmp/opencode/rev/ooc/blit_px_10ns/timing_summary.rpt
report_utilization -file /tmp/opencode/rev/ooc/blit_px_10ns/util.rpt
report_utilization -hierarchical -file /tmp/opencode/rev/ooc/blit_px_10ns/hier.rpt
write_checkpoint -force /tmp/opencode/rev/ooc/blit_px_10ns/ooc_zm_blit_px.dcp
