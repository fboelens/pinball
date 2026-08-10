set result_file [file join $::env(TEMP) pinball_diagonal_bumper.txt]
set result [open $result_file w]
set sample 0

proc sample_diagonal_bumper {} {
    global result sample
    puts $result "$sample x_lo=[debug read memory 0xc000] x=[debug read memory 0xc001] y_lo=[debug read memory 0xc002] y=[debug read memory 0xc003] vx_lo=[debug read memory 0xc004] vx_hi=[debug read memory 0xc005] vy_lo=[debug read memory 0xc006] vy_hi=[debug read memory 0xc007] side=[debug read memory 0xc00c] lock=[debug read memory 0xc009]"
    flush $result
    incr sample
    if {$sample < 16} {
        after time 0.02 sample_diagonal_bumper
    } else {
        close $result
        exit
    }
}

# Bumper2 centre is (152,136), combined collision radius is 14. Approach its
# upper-right quadrant from (ball centre 162,126) with velocity (-2,+2).
after time 7 {
    debug write memory 0xc000 0
    debug write memory 0xc001 154
    debug write memory 0xc002 0
    debug write memory 0xc003 118
    debug write memory 0xc004 0
    debug write memory 0xc005 0xfe
    debug write memory 0xc006 0
    debug write memory 0xc007 2
    debug write memory 0xc008 0
    debug write memory 0xc009 0
    debug write memory 0xc00d 0
    debug write memory 0xc01b 0
    debug write memory 0xc01c 0
    after time 0.01 sample_diagonal_bumper
}
