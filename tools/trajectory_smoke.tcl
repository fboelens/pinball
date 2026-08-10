set trajectory_file [file join $::env(TEMP) pinball_trajectory.txt]
set trajectory_output [open $trajectory_file w]
set trajectory_sample 0

proc sample_trajectory {} {
    global trajectory_output trajectory_sample
    puts $trajectory_output "$trajectory_sample x=[debug read memory 0xc001] y=[debug read memory 0xc003] vx_lo=[debug read memory 0xc004] vx_hi=[debug read memory 0xc005] vy_lo=[debug read memory 0xc006] vy_hi=[debug read memory 0xc007]"
    flush $trajectory_output
    incr trajectory_sample
    if {$trajectory_sample < 30} {
        after time 0.1 sample_trajectory
    } else {
        close $trajectory_output
        exit
    }
}

after time 7 {
    keymatrixdown 8 0x01
}
after time 7.1 {
    keymatrixup 8 0x01
}
after time 7.2 sample_trajectory
