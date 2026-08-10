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

# Passive post at centre (64,56).
after time 7 { inject_ball 42 48 2 }
after time 7.08 {
    set result [file join $::env(TEMP) pinball_object_collision.txt]
    set output [open $result w]
    puts $output "post_x=[debug read memory 0xc001]"
    puts $output "post_vx_lo=[debug read memory 0xc004]"
    puts $output "post_vx_hi=[debug read memory 0xc005]"
    close $output
}

# Bumper3 at centre (176,96), configured with kick=0: passive.
after time 7.15 { inject_ball 154 88 2 }
after time 7.23 {
    set result [file join $::env(TEMP) pinball_object_collision.txt]
    set output [open $result a]
    puts $output "passive_x=[debug read memory 0xc001]"
    puts $output "passive_vx_lo=[debug read memory 0xc004]"
    puts $output "passive_vx_hi=[debug read memory 0xc005]"
    close $output
}

# Bumper1 at centre (64,136), configured with kick=2: active 3 px/frame.
after time 7.30 { inject_ball 42 128 2 }
after time 7.38 {
    set result [file join $::env(TEMP) pinball_object_collision.txt]
    set output [open $result a]
    puts $output "active_x=[debug read memory 0xc001]"
    puts $output "active_vx_lo=[debug read memory 0xc004]"
    puts $output "active_vx_hi=[debug read memory 0xc005]"
    close $output
    exit
}
