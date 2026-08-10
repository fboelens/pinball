# Regression test for passive flipper friction.
#
# A fast, diagonally arriving ball used to have BALL_VX replaced by a fixed
# +/-0.25 value at the first passive contact.  The flipper should now retain
# most of that tangential speed, while adding only a small downhill bias.

set result_file [file join $::env(TEMP) pinball_flipper_momentum.txt]
set output [open $result_file w]
set phase left
set sample 0

proc inject_fast_ball {x vx_lo vx_hi} {
    # BALL_X/Y are 8.8 fixed point; these positions overlap a resting flipper.
    debug write memory 0xc000 0
    debug write memory 0xc001 $x
    debug write memory 0xc002 0
    debug write memory 0xc003 159
    debug write memory 0xc004 $vx_lo
    debug write memory 0xc005 $vx_hi
    debug write memory 0xc006 0
    debug write memory 0xc007 3
    debug write memory 0xc008 0
    debug write memory 0xc009 0
    debug write memory 0xc00d 0
    debug write memory 0xc011 0
    debug write memory 0xc012 0
}

proc sample_momentum {} {
    global output phase sample
    puts $output "$phase $sample x=[debug read memory 0xc001] vx_lo=[debug read memory 0xc004] vx_hi=[debug read memory 0xc005] vy_lo=[debug read memory 0xc006] vy_hi=[debug read memory 0xc007]"
    flush $output
    incr sample

    if {$sample < 6} {
        after time 0.016 sample_momentum
    } elseif {$phase eq "left"} {
        set phase right
        set sample 0
        # Mirror the left test and use -3.0 horizontal velocity.
        inject_fast_ball 119 0 253
        after time 0.016 sample_momentum
    } else {
        close $output
        exit
    }
}

after time 7 {
    # +3.0 horizontal velocity.
    inject_fast_ball 72 0 3
    after time 0.016 sample_momentum
}
