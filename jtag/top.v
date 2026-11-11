// GW_JTAG is a hard silicon primitive, not a simulated or soft TAP.
// nextpnr connects its pads internally; do not enable jtag_as_gpio.
(* blackbox *)
module GW_JTAG (
    input tck_pad_i, tms_pad_i, tdi_pad_i,
    output tdo_pad_o,
    output tck_o, tdi_o, test_logic_reset_o,
    output run_test_idle_er1_o, run_test_idle_er2_o,
    output shift_dr_capture_dr_o, pause_dr_o, update_dr_o,
    output enable_er1_o, enable_er2_o,
    input tdo_er1_i, tdo_er2_i
);
endmodule

module jtag_top (output wire [5:0] led);
    wire tck_raw, tck, tdi, reset_n, scan, update, er1, er2, tdo;

    GW_JTAG tap (
        .tck_o(tck_raw),
        .tdi_o(tdi),
        .test_logic_reset_o(reset_n),
        .shift_dr_capture_dr_o(scan),
        .update_dr_o(update),
        .enable_er1_o(er1),
        .enable_er2_o(er2),
        .tdo_er1_i(1'b0),
        .tdo_er2_i(tdo)
    );

    // Distribute the primitive's TCK on a global clock network, not fabric.
    BUFG tck_buffer (.I(tck_raw), .O(tck));

    mkJtagMailbox mailbox (
        // Despite its name, test_logic_reset_o is active low on this device.
        .CLK(tck), .RST_N(reset_n),
        .pins_selectedWrite(er1), .pins_selectedRead(er2),
        .pins_scan(scan), .pins_update(update), .pins_tdi(tdi),
        .tdo(tdo), .leds(led)
    );
endmodule
