proc inject_ball {x y vy_hi} {
    debug write memory 0xc000 0
    debug write memory 0xc001 $x
    debug write memory 0xc002 0
    debug write memory 0xc003 $y
    debug write memory 0xc004 0
    debug write memory 0xc005 0
    debug write memory 0xc006 0
    debug write memory 0xc007 $vy_hi
    debug write memory 0xc008 0
    debug write memory 0xc009 0
    debug write memory 0xc00d 0
}

# Hold the right flipper and place a slow ball halfway along it.
after time 7 { keymatrixdown 8 0x80 }
after time 7.15 { inject_ball 120 156 1 }
after time 7.23 {
    set result [file join $::env(TEMP) pinball_flipper_roll.txt]
    set output [open $result w]
    puts $output "rolling_x=[debug read memory 0xc001]"
    puts $output "rolling_vx_lo=[debug read memory 0xc004]"
    puts $output "rolling_vx_hi=[debug read memory 0xc005]"
    puts $output "rolling_vy_lo=[debug read memory 0xc006]"
    puts $output "rolling_vy_hi=[debug read memory 0xc007]"
    close $output
}

# At the right-hand pivot the same slow ball must finally be cradled.
after time 7.35 { inject_ball 132 160 1 }
after time 7.50 {
    set result [file join $::env(TEMP) pinball_flipper_roll.txt]
    set output [open $result a]
    puts $output "pivot_vx_lo=[debug read memory 0xc004]"
    puts $output "pivot_vx_hi=[debug read memory 0xc005]"
    puts $output "pivot_vy_lo=[debug read memory 0xc006]"
    puts $output "pivot_vy_hi=[debug read memory 0xc007]"
    close $output
    keymatrixup 8 0x80
    exit
}
