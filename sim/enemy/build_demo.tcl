# Independent build; leaves the user's open Vivado project alone.
set root [file normalize [file join [file dirname [info script]] ../..]]
set out [file join $root build enemy_verify]
file mkdir $out
create_project -in_memory -part xc7a35tcpg236-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
proc add_hdl {dir} {
    foreach item [glob -nocomplain -directory $dir *] {
        if {[file isdirectory $item]} { add_hdl $item } elseif {
            [string tolower [file extension $item]] in {.v .sv .vhd .vhdl}
        } { add_files -norecurse $item }
    }
}
add_hdl [file join $root FDP2026.srcs sources_1 new]
read_xdc [file join $root constraints map_preview.xdc]
set_property top enemy_test_top [current_fileset]
update_compile_order -fileset sources_1
synth_design -top enemy_test_top -part xc7a35tcpg236-1
opt_design
place_design
route_design
report_utilization -file [file join $out utilization.rpt]
report_timing_summary -file [file join $out timing.rpt]
report_drc -file [file join $out drc.rpt]
write_checkpoint -force [file join $out enemy_test_top.dcp]
write_bitstream -force [file join $out enemy_test_top.bit]
puts "ENEMY_DEMO_BUILD: COMPLETE"
