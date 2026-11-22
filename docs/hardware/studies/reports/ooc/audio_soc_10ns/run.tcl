set files {
  /home/matt/projects/ZigMachine/fpga/rtl/audio/zm_audio_soc.v
  /home/matt/projects/ZigMachine/fpga/rtl/audio/zm_audio_core.v
  /home/matt/projects/ZigMachine/fpga/rtl/audio/zm_audio_frac.v
  /home/matt/projects/ZigMachine/fpga/rtl/audio/zm_audio_ym.v
  /home/matt/projects/ZigMachine/fpga/rtl/audio/zm_audio_pokey.v
  /home/matt/projects/ZigMachine/fpga/rtl/audio/zm_audio_pcm.v
  /home/matt/projects/ZigMachine/fpga/rtl/audio/zm_audio_mix.v
  /home/matt/projects/ZigMachine/fpga/rtl/audio/zm_audio_sched.v
  /home/matt/projects/ZigMachine/fpga/rtl/audio/zm_audio_fifo.v
  /home/matt/projects/ZigMachine/fpga/rtl/video/zm_video_sdpram.v
  /home/matt/projects/ZigMachine/fpga/rtl/audio/zm_pokey.v
  /home/matt/projects/ZigMachine/fpga/rtl/audio/zm_pokey_pair.v
  /home/matt/projects/ZigMachine/fpga/rtl/audio/zm_pokey_poly.v
  /home/matt/projects/ZigMachine/fpga/third_party/jt49/hdl/jt49.v
  /home/matt/projects/ZigMachine/fpga/third_party/jt49/hdl/jt49_cen.v
  /home/matt/projects/ZigMachine/fpga/third_party/jt49/hdl/jt49_div.v
  /home/matt/projects/ZigMachine/fpga/third_party/jt49/hdl/jt49_eg.v
  /home/matt/projects/ZigMachine/fpga/third_party/jt49/hdl/jt49_exp.v
  /home/matt/projects/ZigMachine/fpga/third_party/jt49/hdl/jt49_noise.v
}
read_verilog $files
set_property include_dirs {/home/matt/projects/ZigMachine/fpga/gen /home/matt/projects/ZigMachine/fpga/rtl/video /home/matt/projects/ZigMachine/fpga/rtl/blitter /home/matt/projects/ZigMachine/fpga/rtl/audio /home/matt/projects/ZigMachine/fpga/third_party/jt49/hdl} [current_fileset]
synth_design -top zm_audio_soc -part xc7z010clg400-1 -mode out_of_context
opt_design -directive Explore
create_clock -period 10.0 -name clk_ooc [get_ports clk]
place_design -directive ExtraTimingOpt
route_design -directive MoreGlobalIterations
report_timing_summary -file /tmp/opencode/rev/ooc/audio_soc_10ns/timing_summary.rpt
report_utilization -file /tmp/opencode/rev/ooc/audio_soc_10ns/util.rpt
report_utilization -hierarchical -file /tmp/opencode/rev/ooc/audio_soc_10ns/hier.rpt
write_checkpoint -force /tmp/opencode/rev/ooc/audio_soc_10ns/ooc_zm_audio_soc.dcp
