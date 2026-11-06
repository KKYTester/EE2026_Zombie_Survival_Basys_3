# Resolve paths relative to this script, regardless of working directory.
set root_dir [file dirname [file normalize [info script]]]
set project_name FDP2026
if {[info exists ::ee2026_project_name]} {
    set project_name $::ee2026_project_name
}
set project_dir [file join $root_dir build $project_name]

create_project $project_name $project_dir -part xc7a35tcpg236-1

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

# Discover HDL sources and headers, including files in subfolders.
proc collect_hdl_files {directory} {
    set files [list]
    foreach entry [lsort [glob -nocomplain -directory $directory *]] {
        if {[file isdirectory $entry]} {
            set files [concat $files [collect_hdl_files $entry]]
        } elseif {[string tolower [file extension $entry]] in {
            .v .sv .vhd .vhdl .vh .svh
        }} {
            lappend files $entry
        }
    }
    return $files
}

set source_dir [file join $root_dir FDP2026.srcs sources_1 new]
set source_files [collect_hdl_files $source_dir]
if {[llength $source_files] == 0} {
    error "No HDL source files found in $source_dir"
}
add_files -fileset sources_1 -norecurse $source_files
set_property include_dirs [list $source_dir] [get_filesets sources_1]

add_files -fileset constrs_1 -norecurse [list \
    [file join $root_dir FDP2026.srcs constrs_1 new Basys3_Master.xdc] \
    [file join $root_dir constraints enemy_aim.xdc] \
    [file join $root_dir constraints multiplayer_zombie.xdc]]

set_property top My_Top_Module [get_filesets sources_1]
update_compile_order -fileset sources_1
