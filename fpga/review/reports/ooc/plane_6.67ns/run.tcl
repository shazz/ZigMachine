set files {
  /home/matt/projects/ZigMachine/fpga/rtl/video/zm_video_plane.v
}
read_verilog $files
set_property include_dirs {/home/matt/projects/ZigMachine/fpga/gen /home/matt/projects/ZigMachine/fpga/rtl/video /home/matt/projects/ZigMachine/fpga/rtl/blitter /home/matt/projects/ZigMachine/fpga/rtl/audio /home/matt/projects/ZigMachine/fpga/third_party/jt49/hdl} [current_fileset]
synth_design -top zm_video_plane -part xc7z010clg400-1 -mode out_of_context
opt_design -directive Explore
create_clock -period 6.67 -name clk_ooc [get_ports clk]
place_design -directive ExtraTimingOpt
route_design -directive MoreGlobalIterations
report_timing_summary -file /tmp/opencode/rev/ooc/plane_6.67ns/timing_summary.rpt
report_utilization -file /tmp/opencode/rev/ooc/plane_6.67ns/util.rpt
report_utilization -hierarchical -file /tmp/opencode/rev/ooc/plane_6.67ns/hier.rpt
write_checkpoint -force /tmp/opencode/rev/ooc/plane_6.67ns/ooc_zm_video_plane.dcp
