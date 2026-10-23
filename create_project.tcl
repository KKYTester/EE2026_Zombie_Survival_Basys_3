# Resolve paths relative to this script, regardless of working directory.
set root_dir [file dirname [file normalize [info script]]]
set project_dir [file join $root_dir build FDP2026]

create_project FDP2026 $project_dir -part xc7a35tcpg236-1

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

add_files -fileset constrs_1 -norecurse \
    [file join $root_dir FDP2026.srcs constrs_1 new Basys3_Master.xdc]

set_property top My_Top_Module [get_filesets sources_1]
update_compile_order -fileset sources_1
