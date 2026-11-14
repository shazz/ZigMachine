# Dump every leaf cell of a checkpoint as "name ref_name" (then prototypes/lut_diet/probe/group.py
# bills them by hierarchy and by name). Usage: vivado -mode batch -source dump_cells.tcl -tclargs DCP OUT
set_param general.maxThreads 2
lassign $argv dcp out
open_checkpoint $dcp
set f [open $out w]
foreach c [get_cells -hier -filter {IS_PRIMITIVE}] {
    puts $f "[get_property NAME $c] [get_property REF_NAME $c]"
}
close $f
# The LUTs of the RAM wrappers: what drives their inputs and what they drive.
set g [open "$out.sdpram" w]
foreach h {zm_video_out/u_comp/u_fbuf zm_audio_soc/u_core/u_sched/u_q zm_video_out/u_comp/u_mix/u_acc} {
    foreach c [get_cells -hier -filter "IS_PRIMITIVE && NAME =~ $h/* && REF_NAME =~ LUT*"] {
        set ins {}
        foreach p [get_pins -of $c -filter {DIRECTION == IN}] {
            set n [get_nets -of $p]
            if {$n ne ""} { lappend ins [get_property NAME $n] }
        }
        set outs {}
        foreach p [get_pins -of $c -filter {DIRECTION == OUT}] {
            set n [get_nets -of $p]
            if {$n ne ""} { lappend outs [get_property NAME $n] }
        }
        puts $g "[get_property NAME $c] [get_property REF_NAME $c] IN: $ins OUT: $outs"
    }
}
close $g
# The register blocks: the same, for a sample of LUTs (what they compute).
set g [open "$out.regs" w]
foreach h {zm_blit/regs zm_glass_regs zm_video_out/u_comp/u_regs} {
    set i 0
    foreach c [get_cells -hier -filter "IS_PRIMITIVE && NAME =~ $h/* && REF_NAME =~ LUT*"] {
        set ins {}
        foreach p [get_pins -of $c -filter {DIRECTION == IN}] {
            set n [get_nets -of $p]
            if {$n ne ""} { lappend ins [get_property NAME $n] }
        }
        set outs {}
        foreach p [get_pins -of $c -filter {DIRECTION == OUT}] {
            set n [get_nets -of $p]
            if {$n ne ""} { lappend outs [get_property NAME $n] }
        }
        puts $g "[get_property NAME $c] [get_property REF_NAME $c] IN: $ins OUT: $outs"
    }
}
close $g
quit
