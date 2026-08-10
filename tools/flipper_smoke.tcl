# Drop a ball onto the centre of each resting flipper and record the response.
proc inject_ball {x y} {
    debug write memory 0xc000 0
    debug write memory 0xc001 $x
    debug write memory 0xc002 0
    debug write memory 0xc003 $y
    debug write memory 0xc004 0
    debug write memory 0xc005 0
    debug write memory 0xc006 0
    debug write memory 0xc007 3
    debug write memory 0xc008 0
    debug write memory 0xc009 0
    debug write memory 0xc00d 0
}

after time 7 {
    debug write memory 0xc011 0
    inject_ball 72 158
}
after time 7.1 {
    set result [file join $::env(TEMP) pinball_flipper_smoke.txt]
    set output [open $result w]
    puts $output "left_y=[debug read memory 0xc003]"
    puts $output "left_vy_lo=[debug read memory 0xc006]"
    puts $output "left_vy_hi=[debug read memory 0xc007]"
    close $output

    debug write memory 0xc012 0
    inject_ball 120 158
}
after time 7.2 {
    set result [file join $::env(TEMP) pinball_flipper_smoke.txt]
    set output [open $result a]
    puts $output "right_y=[debug read memory 0xc003]"
    puts $output "right_vy_lo=[debug read memory 0xc006]"
    puts $output "right_vy_hi=[debug read memory 0xc007]"
    close $output
    exit
}
