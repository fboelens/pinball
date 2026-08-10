set corner_file [file join $::env(TEMP) pinball_corner_escape.txt]
set corner_output [open $corner_file w]
set corner_sample 0

proc sample_corner {} {
    global corner_output corner_sample
    puts $corner_output "$corner_sample x=[debug read memory 0xc001] y=[debug read memory 0xc003] vx_lo=[debug read memory 0xc004] vx_hi=[debug read memory 0xc005] vy_lo=[debug read memory 0xc006] vy_hi=[debug read memory 0xc007] lock=[debug read memory 0xc009]"
    flush $corner_output
    incr corner_sample
    if {$corner_sample < 30} {
        after time 0.1 sample_corner
    } else {
        close $corner_output
        exit
    }
}

# Approach bumper2 from its wall-facing side.
after time 7 {
    debug write memory 0xc000 0
    debug write memory 0xc001 158
    debug write memory 0xc002 0
    debug write memory 0xc003 128
    debug write memory 0xc004 0
    debug write memory 0xc005 0xff
    debug write memory 0xc006 0
    debug write memory 0xc007 0
    debug write memory 0xc008 0
    debug write memory 0xc009 0
    debug write memory 0xc00d 0
    after time 0.05 sample_corner
}
