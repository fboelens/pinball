proc inject_stationary {center_x center_y} {
    debug write memory 0xc000 0
    debug write memory 0xc001 [expr {$center_x - 8}]
    debug write memory 0xc002 0
    debug write memory 0xc003 [expr {$center_y - 8}]
    debug write memory 0xc004 0
    debug write memory 0xc005 0
    debug write memory 0xc006 0
    debug write memory 0xc007 0
    debug write memory 0xc008 0
    debug write memory 0xc009 0
    debug write memory 0xc00d 0
    debug write memory 0xc01b 0
    debug write memory 0xc01c 0
    debug write memory 0xc01f 0
}

set result_file [file join $::env(TEMP) pinball_polygon_boundary.txt]

# Centre (140,130) lies in the empty upper-left corner of bumper2's old
# bounding circle and must not trigger the polygon bumper.
after time 7 { inject_stationary 140 130 }
after time 7.05 {
    set output [open $result_file w]
    puts $output "clear_x=[debug read memory 0xc001]"
    puts $output "clear_y=[debug read memory 0xc003]"
    puts $output "clear_lock=[debug read memory 0xc009]"
    close $output
}

# Centre (141,138) is within seven pixels of the upper-left diagonal edge and must
# produce one active polygon hit.
after time 7.10 { inject_stationary 141 138 }
after time 7.15 {
    set output [open $result_file a]
    puts $output "touch_x=[debug read memory 0xc001]"
    puts $output "touch_y=[debug read memory 0xc003]"
    puts $output "touch_vx_hi=[debug read memory 0xc005]"
    puts $output "touch_vy_hi=[debug read memory 0xc007]"
    puts $output "touch_side=[debug read memory 0xc00c]"
    puts $output "touch_lock=[debug read memory 0xc009]"
    close $output
    exit
}
