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

# Hold left until it is fully raised, then drop onto it: this must be passive.
after time 7 {
    keymatrixdown 8 0x10
}
after time 7.15 {
    inject_ball 72 158 3
}
after time 7.25 {
    set result [file join $::env(TEMP) pinball_flipper_behavior.txt]
    set output [open $result w]
    puts $output "held_frame=[debug read memory 0xc011]"
    puts $output "held_kick=[debug read memory 0xc016]"
    puts $output "held_vx_lo=[debug read memory 0xc004]"
    puts $output "held_vx_hi=[debug read memory 0xc005]"
    puts $output "held_vy_hi=[debug read memory 0xc007]"
    close $output
    keymatrixup 8 0x10
}

# Start from rest and press as the ball arrives: this must get the hard kick.
after time 7.4 {
    debug write memory 0xc011 0
    inject_ball 72 154 3
    keymatrixdown 8 0x10
}
after time 7.48 {
    set result [file join $::env(TEMP) pinball_flipper_behavior.txt]
    set output [open $result a]
    puts $output "strike_frame=[debug read memory 0xc011]"
    puts $output "strike_vy_hi=[debug read memory 0xc007]"
    close $output
    keymatrixup 8 0x10
}

# Centre the ball in the 16-pixel visual gap. It must continue downward.
after time 7.65 {
    debug write memory 0xc011 0
    debug write memory 0xc012 0
    inject_ball 96 154 3
}
after time 7.78 {
    set result [file join $::env(TEMP) pinball_flipper_behavior.txt]
    set output [open $result a]
    puts $output "gap_y=[debug read memory 0xc003]"
    puts $output "gap_vy_hi=[debug read memory 0xc007]"
    puts $output "gap_waiting=[debug read memory 0xc008]"
    close $output
    exit
}
