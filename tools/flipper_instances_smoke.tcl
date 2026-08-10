# Verify map-driven rendering and collision for the third flipper instance.

set result_file [file join $::env(TEMP) pinball_flipper_instances.txt]
set output [open $result_file w]

proc inject_ball {x y vy_hi} {
    debug write memory 0xc000 0
    debug write memory 0xc001 $x
    debug write memory 0xc002 0
    debug write memory 0xc003 $y
    debug write memory 0xc004 0
    debug write memory 0xc005 0
    debug write memory 0xc006 0
    debug write memory 0xc007 $vy_hi
    debug write memory 0xc008 0
    debug write memory 0xc009 0
    debug write memory 0xc00d 0
}

after time 7 {
    screenshot [file join $::env(TEMP) pinball_three_flippers_rest.png] -raw
    keymatrixdown 8 0x10
}
after time 7.060 {
    screenshot [file join $::env(TEMP) pinball_three_flippers_raised.png] -raw
    keymatrixup 8 0x10
}

# Passive drop near the new left instance: offsets mirror the established lower
# left test relative to its generated pivot (19,116).
after time 7.20 { inject_ball 24 103 3 }
after time 7.27 {
    puts $output "passive x=[debug read memory 0xc001] y=[debug read memory 0xc003] vx=[debug read memory 0xc005]:[debug read memory 0xc004] vy=[debug read memory 0xc007]:[debug read memory 0xc006]"
}

# Active hit near that instance's tip.
after time 7.40 {
    inject_ball 36 96 3
    keymatrixdown 8 0x10
}
after time 7.46 {
    puts $output "active x=[debug read memory 0xc001] y=[debug read memory 0xc003] vx=[debug read memory 0xc005]:[debug read memory 0xc004] vy=[debug read memory 0xc007]:[debug read memory 0xc006]"
    keymatrixup 8 0x10
    close $output
    exit
}
