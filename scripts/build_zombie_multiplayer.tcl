# Create, synthesize, implement, and write the Basys 3 zombie-demo bitstream.
set root_dir [file dirname [file dirname [file normalize [info script]]]]
set_param general.maxThreads 1
set project_setup [file join $root_dir create_zombie_multiplayer.tcl]
set setup_code [catch {source $project_setup} setup_result setup_options]
if {$setup_code != 0 && $setup_code != 2} {
    return -options $setup_options $setup_result
}

reset_run synth_1
reset_run impl_1
launch_runs synth_1 -jobs 1
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "Synthesis status: $synth_status"
if {[string first "Complete" $synth_status] < 0} {
    error "Synthesis failed; see the Vivado run log for diagnostics."
}

launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "Implementation status: $impl_status"
if {[string first "Complete" $impl_status] < 0} {
    error "Implementation/bitstream generation failed; see the Vivado run log."
}

puts "Bitstream: [file join $root_dir build Zombie_Multiplayer_Clean Zombie_Multiplayer_Clean.runs impl_1 My_Top_Module.bit]"
