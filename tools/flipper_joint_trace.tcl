set result_file [file join $::env(TEMP) pinball_flipper_joint_trace.txt]
set output [open $result_file w]
set phase left
set sample 0

proc inject_joint {x} {
    debug write memory 0xc000 0
    debug write memory 0xc001 $x
    debug write memory 0xc002 0
    debug write memory 0xc003 155
    debug write memory 0xc004 0
    debug write memory 0xc005 0
    debug write memory 0xc006 0
    debug write memory 0xc007 0
    debug write memory 0xc008 0
    debug write memory 0xc009 0
    debug write memory 0xc00d 0
    debug write memory 0xc011 0
    debug write memory 0xc012 0
}

proc sample_joint {} {
    global output phase sample
    puts $output "$phase $sample x=[debug read memory 0xc001] y=[debug read memory 0xc003] vx=[debug read memory 0xc005]:[debug read memory 0xc004] vy=[debug read memory 0xc007]:[debug read memory 0xc006]"
    flush $output
    incr sample
    if {$sample < 40} {
        after time 0.016 sample_joint
    } elseif {$phase eq "left"} {
        set phase right
        set sample 0
        inject_joint 126
        after time 0.016 sample_joint
    } else {
        close $output
        exit
    }
}

after time 7 {
    inject_joint 65
    after time 0.016 sample_joint
}
