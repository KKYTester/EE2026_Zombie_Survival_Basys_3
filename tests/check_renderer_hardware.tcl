# Run in an isolated generated directory; does not modify an existing project.
# Optional explicit checkout path; pass Windows paths with forward slashes.
if {$argc > 0} {
    set root_dir [lindex $argv 0]
} else {
    set root_dir [file dirname [file dirname [file join [pwd] [info script]]]]
}
set out_dir [file join $root_dir build renderer_hardware]
if {$argc > 1} { set out_dir [file normalize [lindex $argv 1]] }
file mkdir $out_dir
cd $out_dir
set_param general.maxThreads 8
set source_dir [file join $root_dir FDP2026.srcs sources_1 new]
proc read_design_tree {directory} {
    foreach source [lsort [glob -nocomplain -directory $directory *]] {
        if {[file isdirectory $source]} { read_design_tree $source
        } elseif {[file extension $source] eq ".v"} { read_verilog [list $source]
        } elseif {[file extension $source] eq ".vhd"} { read_vhdl [list $source] }
    }
}
read_design_tree $source_dir
set_property include_dirs [list $source_dir] [current_fileset]
read_xdc [list [file join $root_dir FDP2026.srcs constrs_1 new Basys3_Master.xdc]]
read_xdc [list [file join $root_dir constraints multiplayer_zombie.xdc]]
synth_design -top My_Top_Module -part xc7a35tcpg236-1
if {[llength [get_clocks -quiet {sys_clk_pin oled_clk}]] != 2} {
    error "Missing board or OLED timing clock"
}
report_utilization -file synthesis_utilization.rpt
report_utilization -hierarchical -file synthesis_hierarchy.rpt
report_timing_summary -file synthesis_timing.rpt
write_checkpoint -force synthesized.dcp
opt_design
place_design
phys_opt_design
route_design
report_utilization -file implemented_utilization.rpt
report_utilization -hierarchical -file implemented_hierarchy.rpt
report_timing_summary -delay_type min_max -report_unconstrained -file implemented_timing.rpt
report_timing -delay_type max -max_paths 120 -nworst 1 -file critical_paths.rpt
report_high_fanout_nets -timing -max_nets 30 -file high_fanout.rpt
report_drc -file implemented_drc.rpt
report_cdc -file implemented_cdc.rpt
write_checkpoint -force routed.dcp
if {[get_property SLACK [get_timing_paths -delay_type max -max_paths 1]] < 0 ||
    [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]] < 0} {
    error "Routed internal setup or hold timing failed; inspect implemented_timing.rpt"
}
