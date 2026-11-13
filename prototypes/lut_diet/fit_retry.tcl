# A placement retry from a build's synthesis checkpoint (same netlist, so same CSR map): the
# build's own opt passes, then each placer directive in turn until one places, phys_opt, the
# re-route that closed the desk build (NoTimingRelaxation + phys_opt AggressiveExplore), and the
# first routed design that meets setup and hold is written as a bitstream.
# vivado -mode batch -source fit_retry.tcl -tclargs SYNTH_DCP XDC OUTDIR
set_param general.maxThreads 2
lassign $argv dcp xdc out
file mkdir $out
proc met {tag} {
    set s [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
    set h [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
    puts "FIT $tag WNS=$s WHS=$h"
    return [expr {$s >= 0 && $h >= 0}]
}
proc finish {tag} {
    global out
    write_checkpoint -force $out/platform_z7_route.dcp
    report_timing_summary -datasheet -max_paths 10 -file $out/platform_z7_timing.rpt
    report_utilization -file $out/platform_z7_utilization_route.rpt
    report_route_status -file $out/platform_z7_route_status.rpt
    report_drc -file $out/platform_z7_drc.rpt
    write_bitstream -force $out/platform_z7.bit
    puts "FIT_DONE $tag"
    quit
}
open_checkpoint $dcp
read_xdc $xdc
opt_design -directive ExploreArea
opt_design -control_set_merge -merge_equivalent_drivers
write_checkpoint -force $out/platform_z7_opt.dcp
report_utilization -file $out/platform_z7_utilization_opt.rpt
foreach pd {ExtraTimingOpt Default Explore AltSpreadLogic_high SpreadLogic_high ExtraPostPlacementOpt} {
    open_checkpoint $out/platform_z7_opt.dcp
    if {[catch {place_design -directive $pd} err]} {
        puts "FIT place $pd FAILED: $err"
        close_design
        continue
    }
    puts "FIT placed with $pd"
    phys_opt_design -directive AggressiveExplore
    write_checkpoint -force $out/platform_z7_place_$pd.dcp
    report_utilization -file $out/platform_z7_utilization_place_$pd.rpt
    foreach rd {NoTimingRelaxation AggressiveExplore} {
        route_design -directive $rd
        if {[met "$pd-$rd"]} { finish "$pd-$rd" }
        phys_opt_design -directive AggressiveExplore
        if {[met "$pd-$rd-po"]} { finish "$pd-$rd-po" }
        report_timing_summary -file $out/timing_${pd}_$rd.rpt
        open_checkpoint $out/platform_z7_place_$pd.dcp
    }
    close_design
}
puts "FIT_FAILED"
quit
