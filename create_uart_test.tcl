# Build a small, standalone Basys 3 project for the two-board UART test.
# Run this script from Vivado's Tcl console. Paths are relative to this file.
set root_dir [file dirname [file normalize [info script]]]
set project_dir [file join $root_dir build UART_Board_Test]

if {[file exists $project_dir]} {
    open_project [file join $project_dir UART_Board_Test.xpr]
    return
}

create_project UART_Board_Test $project_dir -part xc7a35tcpg236-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set source_dir [file join $root_dir FDP2026.srcs sources_1 new uart]
set design_files [list \
    [file join $source_dir baud_gen.v] \
    [file join $source_dir uart_tx.v] \
    [file join $source_dir uart_rx.v] \
    [file join $source_dir packet_tx.v] \
    [file join $source_dir packet_rx.v] \
    [file join $source_dir multiplayer_link.v] \
    [file join $root_dir FDP2026.srcs sources_1 new demo uart_test_top.v]]
add_files -fileset sources_1 -norecurse $design_files
add_files -fileset constrs_1 -norecurse \
    [file join $root_dir constraints uart_test.xdc]
set_property top uart_test_top [get_filesets sources_1]
update_compile_order -fileset sources_1
