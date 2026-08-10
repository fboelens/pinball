# Inject an upward-moving ball under the top collision row and record velocity.
after time 7 {
    debug write memory 0xc000 0
    debug write memory 0xc001 120
    debug write memory 0xc002 0
    debug write memory 0xc003 7
    debug write memory 0xc004 0
    debug write memory 0xc005 0
    debug write memory 0xc006 0
    debug write memory 0xc007 0xfc
    debug write memory 0xc008 0
    after frame {
        after frame {
            set result [file join $::env(TEMP) pinball_collision_smoke.txt]
            set output [open $result w]
            puts $output "vx_lo=[debug read memory 0xc004]"
            puts $output "vx_hi=[debug read memory 0xc005]"
            puts $output "vy_lo=[debug read memory 0xc006]"
            puts $output "vy_hi=[debug read memory 0xc007]"
            puts $output "y_hi=[debug read memory 0xc003]"
            close $output
            exit
        }
    }
}
