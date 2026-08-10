proc inject_ball {x y vx_hi} {
    debug write memory 0xc000 0
    debug write memory 0xc001 $x
    debug write memory 0xc002 0
    debug write memory 0xc003 $y
    debug write memory 0xc004 0
    debug write memory 0xc005 $vx_hi
    debug write memory 0xc006 0
    debug write memory 0xc007 0
    debug write memory 0xc008 0
    debug write memory 0xc009 0
    debug write memory 0xc00d 0
}

after time 7 {
    screenshot [file join $::env(TEMP) pinball_object_normal.png] -raw
    inject_ball 42 48 2
}
after time 7.07 {
    screenshot [file join $::env(TEMP) pinball_object_hit.png] -raw
}
after time 7.28 {
    screenshot [file join $::env(TEMP) pinball_object_restored.png] -raw
    set result [file join $::env(TEMP) pinball_object_animation.txt]
    set output [open $result w]
    puts $output "timer=[debug read memory 0xc022]"
    puts $output "source=[debug read memory 0xc023]"
    puts $output "target_x=[debug read memory 0xc024]"
    puts $output "target_y=[debug read memory 0xc025]"
    close $output
    exit
}
