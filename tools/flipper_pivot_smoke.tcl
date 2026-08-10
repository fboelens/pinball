set result_file [file join $::env(TEMP) pinball_flipper_pivot.txt]
set output [open $result_file w]

after time 7 {
    global output
    puts $output "rest=[debug read memory 0xc011]"
    screenshot [file join $::env(TEMP) pinball_flipper_rest.png] -raw
    keymatrixdown 8 0x10
}
after time 7.018 {
    global output
    puts $output "moving=[debug read memory 0xc011]"
    screenshot [file join $::env(TEMP) pinball_flipper_moving.png] -raw
}
after time 7.060 {
    global output
    puts $output "raised=[debug read memory 0xc011]"
    screenshot [file join $::env(TEMP) pinball_flipper_raised.png] -raw
    keymatrixup 8 0x10
    close $output
    exit
}
