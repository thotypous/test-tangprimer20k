package JtagMailbox;

// All state uses the JTAG TCK domain; no clock-domain crossing is needed.
// ER1 (IR 0x42): write a 32-bit word, LSB first; commit on Update-DR.
// ER2 (IR 0x43): read {"JTAG", writeCount, word + 1}, 96 bits, LSB first.
// Reading ER2 has no side effects. Arithmetic wraps modulo 2^32.
interface JtagMailbox;
    (* always_ready, always_enabled *)
    method Action pins(Bool selectedWrite, Bool selectedRead,
                       Bool scan, Bool update, Bit#(1) tdi);
    (* always_ready *)
    method Bit#(1) tdo;
    (* always_ready *)
    method Bit#(6) leds;
endinterface

(* synthesize *)
module mkJtagMailbox(JtagMailbox);
    Reg#(Bit#(32)) incoming <- mkReg(0);
    Reg#(Bit#(32)) reply <- mkReg(0);
    Reg#(Bit#(32)) writeCount <- mkReg(0);
    Reg#(Bit#(96)) outgoing <- mkReg(0);
    Reg#(Bool) holdScan <- mkReg(False);
    Reg#(Bool) wasUpdate <- mkReg(False);

    method Action pins(Bool selectedWrite, Bool selectedRead,
                       Bool scan, Bool update, Bit#(1) tdi);
        // GW_JTAG exposes a combined capture/shift signal. Preload whenever
        // not scanning, but hold the data through Exit/Pause until Update-DR.
        if (scan)
            holdScan <= True;
        else if (update)
            holdScan <= False;
        wasUpdate <= update;

        if (selectedWrite && scan)
            incoming <= {tdi, incoming[31:1]};

        if (selectedWrite && update && !wasUpdate) begin
            reply <= incoming + 1;
            writeCount <= writeCount + 1;
        end

        if (selectedRead) begin
            if (scan)
                outgoing <= {tdi, outgoing[95:1]};
            else if (!holdScan && !update)
                outgoing <= {32'h4a544147, writeCount, reply};
        end
    endmethod

    method Bit#(1) tdo = outgoing[0];
    method Bit#(6) leds = ~truncate(reply);
endmodule

endpackage
