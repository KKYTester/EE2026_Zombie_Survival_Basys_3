# Build the integrated two-board zombie game. Run from Vivado's Tcl console.
proc create_or_open_zombie_project {root_dir} {
set project_dir [file join $root_dir build Zombie_Multiplayer_Clean]
set project_file [file join $project_dir Zombie_Multiplayer_Clean.xpr]
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

if {[file exists $project_file]} {
    open_project $project_file
} else {
    if {[file exists $project_dir]} {
        error "Project directory exists without $project_file. Preserve it and choose a new build folder."
    }
    create_project Zombie_Multiplayer_Clean $project_dir -part xc7a35tcpg236-1
    set_property target_language Verilog [current_project]
    set_property simulator_language Mixed [current_project]
}

set source_dir [file join $root_dir FDP2026.srcs sources_1 new]
set source_files [collect_hdl_files $source_dir]
if {[llength $source_files] == 0} {
    error "No HDL sources found in $source_dir"
}
set source_set [get_filesets sources_1]
set constraint_set [get_filesets constrs_1]
foreach source_file $source_files {
    set normalized [file normalize $source_file]
    set found 0
    foreach existing [get_files -quiet -of_objects $source_set] {
        if {[file normalize $existing] eq $normalized} { set found 1; break }
    }
    if {!$found} { add_files -fileset sources_1 -norecurse $normalized }
}
set constraint_files [list \
    [file join $root_dir FDP2026.srcs constrs_1 new Basys3_Master.xdc] \
    [file join $root_dir constraints enemy_aim.xdc] \
    [file join $root_dir constraints multiplayer_zombie.xdc]]
foreach constraint_file $constraint_files {
    set normalized [file normalize $constraint_file]
    set found 0
    foreach existing [get_files -quiet -of_objects $constraint_set] {
        if {[file normalize $existing] eq $normalized} { set found 1; break }
    }
    if {!$found} { add_files -fileset constrs_1 -norecurse $normalized }
}
set_property top My_Top_Module $source_set
update_compile_order -fileset sources_1
}

set root_dir [file dirname [file normalize [info script]]]
create_or_open_zombie_project $root_dir
