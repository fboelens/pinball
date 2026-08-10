# Trace a slow ball rolling across each resting flipper's rounded inner tip.
# The nearest-sample selector must remain stable and the ball must leave the cap
# toward the centre drain without position correction or velocity oscillation.

set result_file [file join $::env(TEMP) pinball_flipper_tip_trace.txt]
set output [open $result_file w]
set phase left
set sample 0

proc inject_tip_ball {x vx_lo vx_hi} {
    debug write memory 0xc000 0
    debug write memory 0xc001 $x
    debug write memory 0xc002 0
    debug write memory 0xc003 163
    debug write memory 0xc004 $vx_lo
    debug write memory 0xc005 $vx_hi
    debug write memory 0xc006 64
    debug write memory 0xc007 0
    debug write memory 0xc008 0
    debug write memory 0xc009 0
    debug write memory 0xc00d 0
    debug write memory 0xc011 0
    debug write memory 0xc012 0
}

proc sample_tip {} {
    global output phase sample
    puts $output "$phase $sample x=[debug read memory 0xc001] y=[debug read memory 0xc003] vx=[debug read memory 0xc005]:[debug read memory 0xc004] vy=[debug read memory 0xc007]:[debug read memory 0xc006]"
    flush $output
    incr sample
    if {$sample < 24} {
        after time 0.016 sample_tip
    } elseif {$phase eq "left"} {
        set phase right
        set sample 0
        # Centres mirror around x=207: left centre 88 -> right centre 119.
        inject_tip_ball 111 0 255
        after time 0.016 sample_tip
    } else {
        close $output
        exit
    }
}

after time 7 {
    # Top-left x=80 gives centre x=88, moving toward the left flipper tip.
    inject_tip_ball 80 0 1
    after time 0.016 sample_tip
}
