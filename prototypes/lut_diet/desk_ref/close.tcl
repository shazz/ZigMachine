# Incremental timing closure of build/board_desk_bars (same netlist, so same CSR map):
# A) more post-route phys_opt passes on the routed DCP; B) re-route the placed DCP with other
# router directives. Writes the first DCP + bitstream that meets setup and hold.
set_param general.maxThreads 2
set G /home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/build/board_desk_bars/gateware
set O /home/matt/projects/ZigMachine/.claude/worktrees/agent-aecf7bd3f6c84a722/fpga/build/board_desk_bars_pr
proc met {tag} {
    set s [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
    set h [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
    puts "CLOSE $tag WNS=$s WHS=$h"
    return [expr {$s >= 0 && $h >= 0}]
}
proc finish {tag} {
    global O
    write_checkpoint -force $O/platform_z7_route.dcp
    report_timing_summary -datasheet -max_paths 10 -file $O/platform_z7_timing.rpt
    report_utilization -file $O/platform_z7_utilization_route.rpt
    report_route_status -file $O/platform_z7_route_status.rpt
    report_drc -file $O/platform_z7_drc.rpt
    write_bitstream -force $O/platform_z7.bit
    puts "CLOSE_DONE $tag"
    quit
}
open_checkpoint $G/platform_z7_route.dcp
met start
foreach d {Explore AggressiveFanoutOpt AlternateReplication AggressiveExplore} {
    phys_opt_design -directive $d
    if {[met "A-$d"]} { finish "A-$d" }
}
close_design
foreach rd {NoTimingRelaxation Explore HigherDelayCost} {
    open_checkpoint $G/platform_z7_place.dcp
    route_design -directive $rd
    if {[met "B-$rd"]} { finish "B-$rd" }
    phys_opt_design -directive AggressiveExplore
    if {[met "B-$rd-po"]} { finish "B-$rd-po" }
    phys_opt_design -directive AlternateReplication
    if {[met "B-$rd-po2"]} { finish "B-$rd-po2" }
    close_design
}
puts "CLOSE_FAILED"
quit
