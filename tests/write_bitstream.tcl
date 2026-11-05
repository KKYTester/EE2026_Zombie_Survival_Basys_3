# Run after run_renderer_checks.ps1 -Hardware. Opens only generated output.
if {$argc > 0} {
    set root_dir [lindex $argv 0]
} else {
    set root_dir [file dirname [file dirname [file normalize [info script]]]]
}
set out_dir [file join $root_dir build renderer_hardware]
open_checkpoint [file join $out_dir routed.dcp]
set setup_path [get_timing_paths -delay_type max -max_paths 1]
set hold_path [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup_path] == 0 || [llength $hold_path] == 0} {
    error "Missing timing paths; run hardware validation first"
}
if {[get_property SLACK $setup_path] < 0 || [get_property SLACK $hold_path] < 0} {
    error "Internal setup or hold timing failed; bitstream was not generated"
}
write_bitstream -force [file join $out_dir My_Top_Module.bit]
