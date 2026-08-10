after time 7 {
    set result [file join $::env(TEMP) pinball_boot_trace.txt]
    set output [open $result w]
    puts $output "pc=[reg PC] sp=[reg SP]"
    puts $output "rom4000=[debug read memory 0x4000] rom8000=[debug read memory 0x8000]"
    puts $output "waiting=[debug read memory 0xc008] anim=[debug read memory 0xc022]"
    close $output
    exit
}
