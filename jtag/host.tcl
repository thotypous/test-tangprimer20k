# Run with OpenOCD after loading build/jtag.fs. Set JTAG_WORD for one exchange;
# otherwise exercise boundary values, alternating bits and all 32 walking bits.
proc read_reply {} {
    irscan gowin.tap 0x43
    set words [drscan gowin.tap 32 0 32 0 32 0]
    scan [lindex $words 0] %x reply
    scan [lindex $words 1] %x count
    scan [lindex $words 2] %x magic
    if {$magic != 0x4a544147} {
        error [format "Wrong mailbox signature: 0x%08x (expected 0x4a544147); load the JTAG example first" $magic]
    }
    return [list $reply $count]
}

proc exchange {word previous_count} {
    irscan gowin.tap 0x42
    drscan gowin.tap 32 [format 0x%08x $word]
    set result [read_reply]
    set expected [expr {($word + 1) & 0xffffffff}]
    set expected_count [expr {($previous_count + 1) & 0xffffffff}]
    if {[lindex $result 0] != $expected || [lindex $result 1] != $expected_count} {
        error [format "FAIL TX=0x%08x RX=0x%08x expected=0x%08x count=%u expected_count=%u" $word [lindex $result 0] $expected [lindex $result 1] $expected_count]
    }
    # A read must not process another command or alter the stored response.
    if {[read_reply] ne $result} {
        error "FAIL: repeated read changed the response or write count"
    }
    puts [format "TX 0x%08x -> RX 0x%08x  count=%u" $word [lindex $result 0] [lindex $result 1]]
    return [lindex $result 1]
}

init
set status [catch {
    set count [lindex [read_reply] 1]
    if {[info exists ::env(JTAG_WORD)]} {
        set patterns [list [expr {$::env(JTAG_WORD) & 0xffffffff}]]
    } else {
        set patterns {0x00000000 0xffffffff 0x12345678 0x80000000 0xaaaaaaaa 0x55555555}
        for {set bit 0} {$bit < 32} {incr bit} {
            lappend patterns [expr {1 << $bit}]
        }
    }
    foreach word $patterns {
        set count [exchange $word $count]
    }
    puts "PASS: [llength $patterns] PC-to-FPGA commands and checked FPGA-to-PC responses via JTAG"
} message]
# Leave a harmless instruction selected; do not reset/reconfigure the FPGA.
if {$status} {
    puts stderr $message
    shutdown error
} else {
    irscan gowin.tap 0xff
    shutdown
}
