set result_file [file join $::env(TEMP) pinball_flipper_mirror.txt]

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
    debug write memory 0xc011 0
    debug write memory 0xc012 0
}

proc append_velocity {label} {
    global result_file
    set output [open $result_file a]
    puts $output "$label vx_lo=[debug read memory 0xc004] vx_hi=[debug read memory 0xc005] vy_lo=[debug read memory 0xc006] vy_hi=[debug read memory 0xc007]"
    close $output
}

after time 7 {
    set output [open $result_file w]
    close $output
    inject_ball 84 152 3
    keymatrixdown 8 0x10
}
after time 7.060 { append_velocity left_tip; keymatrixup 8 0x10 }

# Mirror centre X around the two pivots: 92 -> 115.
after time 7.20 { inject_ball 107 152 3; keymatrixdown 8 0x80 }
after time 7.260 { append_velocity right_tip; keymatrixup 8 0x80 }

after time 7.40 { inject_ball 60 156 3; keymatrixdown 8 0x10 }
after time 7.460 { append_velocity left_base; keymatrixup 8 0x10 }

# Mirror centre X around the two pivots: 68 -> 139.
after time 7.60 { inject_ball 131 156 3; keymatrixdown 8 0x80 }
after time 7.660 {
    append_velocity right_base
    keymatrixup 8 0x80
}

# A moving rigid flipper must also catch an already rising ball. Stationary
# flippers now detect both faces, with the underside returning the ball down.
after time 7.80 { inject_ball 84 153 0xff; keymatrixdown 8 0x10 }
after time 7.850 { append_velocity left_rising; keymatrixup 8 0x10 }
after time 8.00 { inject_ball 107 153 0xff; keymatrixdown 8 0x80 }
after time 8.050 {
    append_velocity right_rising
    keymatrixup 8 0x80
    exit
}
