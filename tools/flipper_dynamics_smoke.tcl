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

# A slow ball on a held flipper must stay supported and roll along its slope.
# It must not be glued to zero velocity; the recorded values expose regressions
# that reintroduce a hard stop or repeated-contact energy gain.
after time 7 { keymatrixdown 8 0x10 }
after time 7.15 { inject_ball 60 160 1 }
after time 7.35 {
    set result [file join $::env(TEMP) pinball_flipper_dynamics.txt]
    set output [open $result w]
    puts $output "cradle_vx_lo=[debug read memory 0xc004]"
    puts $output "cradle_vx_hi=[debug read memory 0xc005]"
    puts $output "cradle_vy_lo=[debug read memory 0xc006]"
    puts $output "cradle_vy_hi=[debug read memory 0xc007]"
    close $output
    keymatrixup 8 0x10
}
after time 7.48 {
    set result [file join $::env(TEMP) pinball_flipper_dynamics.txt]
    set output [open $result a]
    puts $output "released_y=[debug read memory 0xc003]"
    puts $output "released_vy_lo=[debug read memory 0xc006]"
    puts $output "released_vy_hi=[debug read memory 0xc007]"
    close $output
}

# Hit close to the left pivot during the rising stroke.
after time 7.55 {
    debug write memory 0xc011 0
    inject_ball 60 156 3
    keymatrixdown 8 0x10
}
after time 7.61 {
    set result [file join $::env(TEMP) pinball_flipper_dynamics.txt]
    set output [open $result a]
    puts $output "base_vy_lo=[debug read memory 0xc006]"
    puts $output "base_vy_hi=[debug read memory 0xc007]"
    close $output
    keymatrixup 8 0x10
}

# Hit the tip under otherwise identical conditions.
after time 7.85 {
    debug write memory 0xc011 0
    inject_ball 84 152 3
    keymatrixdown 8 0x10
}
after time 7.91 {
    set result [file join $::env(TEMP) pinball_flipper_dynamics.txt]
    set output [open $result a]
    puts $output "tip_vy_lo=[debug read memory 0xc006]"
    puts $output "tip_vy_hi=[debug read memory 0xc007]"
    close $output
    keymatrixup 8 0x10
    exit
}
