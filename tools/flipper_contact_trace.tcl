set result_file [file join $::env(TEMP) pinball_flipper_contact_trace.txt]
set output [open $result_file w]
set sample 0

proc sample_flipper_contact {} {
    global output sample
    puts $output "$sample frame=[debug read memory 0xc011] kick=[debug read memory 0xc016] x=[debug read memory 0xc001] y=[debug read memory 0xc003] vx_lo=[debug read memory 0xc004] vx_hi=[debug read memory 0xc005] vy_lo=[debug read memory 0xc006] vy_hi=[debug read memory 0xc007]"
    flush $output
    incr sample
    if {$sample < 12} {
        after time 0.016 sample_flipper_contact
    } else {
        keymatrixup 8 0x10
        close $output
        exit
    }
}

after time 7 {
    debug write memory 0xc000 0
    debug write memory 0xc001 60
    debug write memory 0xc002 0
    debug write memory 0xc003 156
    debug write memory 0xc004 0
    debug write memory 0xc005 0
    debug write memory 0xc006 0
    debug write memory 0xc007 3
    debug write memory 0xc008 0
    debug write memory 0xc009 0
    debug write memory 0xc00d 0
    debug write memory 0xc011 0
    keymatrixdown 8 0x10
    after time 0.005 sample_flipper_contact
}
