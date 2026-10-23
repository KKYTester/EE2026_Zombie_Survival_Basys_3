# Resolve paths relative to this script, regardless of working directory.
set root_dir [file dirname [file normalize [info script]]]
set project_dir [file join $root_dir build FDP2026]

create_project FDP2026 $project_dir -part xc7a35tcpg236-1

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set source_dir [file join $root_dir FDP2026.srcs sources_1 new]

add_files -fileset sources_1 -norecurse [list \
    [file join $source_dir Ps2Interface.vhd] \
    [file join $source_dir Mouse_Control.vhd] \
    [file join $source_dir Oled_Display.v] \
    [file join $source_dir My_Top_Module.v] \
]

add_files -fileset constrs_1 -norecurse \
    [file join $root_dir FDP2026.srcs constrs_1 new Basys3_Master.xdc]

set_property top My_Top_Module [get_filesets sources_1]
update_compile_order -fileset sources_1