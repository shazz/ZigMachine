# From the desk build's synthesis checkpoint: the build's own opt passes, then the stronger area
# passes Vivado offers, the LUT count after each (zero RTL change). Then the QoR suggestions.
# vivado -mode batch -source opt_variants.tcl -tclargs SYNTH_DCP OUTDIR
set_param general.maxThreads 2
lassign $argv dcp out
file mkdir $out
proc luts {tag} {
    global out
    report_utilization -file $out/util_$tag.rpt
    set f [open $out/util_$tag.rpt]; set t [read $f]; close $f
    regexp {Slice LUTs\*?\s*\|\s*(\d+)} $t -> n
    regexp {Slice Registers\s*\|\s*(\d+)} $t -> r
    puts "LUTS $tag $n FF $r"
}
open_checkpoint $dcp
luts synth
opt_design -directive ExploreArea
luts explorearea
opt_design -control_set_merge -merge_equivalent_drivers
luts csmerge
report_control_sets -file $out/cs_after_merge.rpt
opt_design -resynth_seq_area
luts resynth_seq_area
opt_design -aggressive_remap
luts aggressive_remap
opt_design -resynth_area
luts resynth_area
write_checkpoint -force $out/opt_max.dcp
report_qor_suggestions -file $out/qor_suggestions.rpt
quit
