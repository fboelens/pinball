set result_file [file join $::env(TEMP) pinball_flipper_rest_mirror.txt]
set output [open $result_file w]
set phase left
set sample 0

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
    debug write memory 0xc011 0
    debug write memory 0xc012 0
}

proc sample_rest_flipper {} {
    global output phase sample
    puts $output "$phase $sample x=[debug read memory 0xc001] y=[debug read memory 0xc003] vx_lo=[debug read memory 0xc004] vx_hi=[debug read memory 0xc005] vy_lo=[debug read memory 0xc006] vy_hi=[debug read memory 0xc007]"
    flush $output
    incr sample
    if {$sample < 8} {
        after time 0.05 sample_rest_flipper
    } elseif {$phase eq "left"} {
        set phase right
        set sample 0
        # Centre X 80 mirrors to 127 around pivot sum 207.
        inject_ball 119 159
        after time 0.01 sample_rest_flipper
    } else {
        close $output
        exit
    }
}

after time 7 {
    inject_ball 72 159
    after time 0.01 sample_rest_flipper
}
