# Run in an isolated generated directory; does not modify an existing project.
# Optional explicit checkout path; pass Windows paths with forward slashes.
if {$argc > 0} {
    set root_dir [lindex $argv 0]
} else {
    set root_dir [file dirname [file dirname [file join [pwd] [info script]]]]
}
set out_dir [file join $root_dir build renderer_hardware]
file mkdir $out_dir
cd $out_dir
set source_dir [file join $root_dir FDP2026.srcs sources_1 new]
foreach source {Clk_Divider.v Oled_Display.v Player.v Button_Debounce.v Player_Controller.v Ray_Caster.v Map_Renderer.v My_Top_Module.v} {
    read_verilog [list [file join $source_dir $source]]
}
foreach source {Ps2Interface.vhd Mouse_Control.vhd} {
    read_vhdl [list [file join $source_dir $source]]
}
set_property include_dirs [list $source_dir] [current_fileset]
read_xdc [list [file join $root_dir FDP2026.srcs constrs_1 new Basys3_Master.xdc]]
synth_design -top My_Top_Module -part xc7a35tcpg236-1
report_utilization -file synthesis_utilization.rpt
report_timing_summary -file synthesis_timing.rpt
opt_design
place_design
phys_opt_design
route_design
report_utilization -file implemented_utilization.rpt
report_timing_summary -delay_type min_max -report_unconstrained -file implemented_timing.rpt
report_drc -file implemented_drc.rpt
report_cdc -file implemented_cdc.rpt
write_checkpoint -force routed.dcp
if {[get_property SLACK [get_timing_paths -delay_type max -max_paths 1]] < 0 ||
    [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]] < 0} {
    error "Routed internal setup or hold timing failed; inspect implemented_timing.rpt"
}
