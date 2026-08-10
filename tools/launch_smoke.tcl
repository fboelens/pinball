# Launch once, release space and record the ball after two emulated seconds.
after time 7 {
    keymatrixdown 8 0x01
}
after time 7.2 {
    keymatrixup 8 0x01
}
after time 9 {
    set result [file join $::env(TEMP) pinball_launch_smoke.txt]
    set output [open $result w]
    puts $output "x_hi=[debug read memory 0xc001]"
    puts $output "y_hi=[debug read memory 0xc003]"
    puts $output "vx_hi=[debug read memory 0xc005]"
    puts $output "vy_hi=[debug read memory 0xc007]"
    puts $output "waiting=[debug read memory 0xc008]"
    close $output
    screenshot [file join $::env(TEMP) pinball_launch_smoke.png] -raw
    exit
}
