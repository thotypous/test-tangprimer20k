# Tang Primer 20K JTAG mailbox

A Bluespec example for the Sipeed Tang Primer 20K with the Dock baseboard that exchanges data with the PC through the FPGA's **hard JTAG user registers**, not UART.

Built, loaded, and tested on the connected board. All programming commands load **volatile SRAM only**. SPI flash is unchanged; power cycling restores its existing image.

## Requirements

Tools on `PATH`:

- GNU Make
- Yosys with `synth_gowin`
- nextpnr-himbaechel with Gowin support
- Apicula (`gowin_pack` and device databases)
- openFPGALoader with the `tangprimer20k` board definition
- Bluespec compiler (`bsc`) and OpenOCD for the JTAG mailbox

The example requires **GW_JTAG support in both nextpnr and Apicula**, including the `GW2A-18C` database and JTAG configuration fuses. The installed toolchain supports these; a toolchain without that support cannot build this example. The target is `GW2A-LV18PG256C8/I7`, using the `GW2A-18C` database for its hard-JTAG support.

Connect the Dock's USB-JTAG port. Its Sipeed debugger enumerates as an FT2232-compatible device (`0403:6010`); OpenOCD uses channel A. The current Linux user needs USB access. No extra wiring or serial-port connection is needed.

On Dock revisions older than V3714, set **DIP1 down/ON** to enable the FPGA. V3714 and newer do not use DIP1 as the enable switch. See [Sipeed's board-enable guidance](https://wiki.sipeed.com/hardware/en/tang/tang-primer-20k/primer-20k.html#Dock-ext-board-not-work).

Run commands from the repository root. Close other programs using the JTAG adapter first.

## Build, program, and test

```sh
make detect                            # Read the FPGA ID over JTAG
make                                   # Build build/jtag.fs (default target)
make jtag                              # Build build/jtag.fs
make program-jtag                      # Build if needed, then load SRAM
make test-jtag                         # Exercise the loaded mailbox
make exchange-jtag WORD=0x12345678      # Send one word and check its response
```

Load the mailbox before running either host command. The host commands do not load a bitstream.

The PC writes a 32-bit word, and the FPGA returns that word plus one, modulo 2^32, together with a write counter. The LEDs display the low six bits of the result. A TAP reset clears the mailbox state; OpenOCD initializes the TAP when it connects.

Observed single-word exchange:

```text
TX 0x12345678 -> RX 0x12345679  count=1
PASS: 1 PC-to-FPGA commands and checked FPGA-to-PC responses via JTAG
```

### Wire protocol

The Gowin TAP has an 8-bit instruction register. All data registers shift least-significant bit first.

| Instruction | Operation | Data |
| --- | --- | --- |
| `0x42` (ER1) | Write a request | 32-bit word; committed on Update-DR |
| `0x43` (ER2) | Read a response | 96 bits, as described below |

| Response bits | Meaning |
| --- | --- |
| `[31:0]` | Request plus one, modulo 2^32 |
| `[63:32]` | Number of committed writes, modulo 2^32 |
| `[95:64]` | Signature `0x4a544147` (ASCII `JTAG`) |

ER2 reads do not change the response or write count. The host checks the signature, arithmetic result, count increment, and stability across repeated reads.

### Implementation

| File | Role |
| --- | --- |
| `jtag/JtagMailbox.bsv` | Bluespec shift registers, request processing, response, and LEDs |
| `jtag/top.v` | Silicon `GW_JTAG` declaration, clock buffer, and Bluespec connection |
| `jtag/primer20k.cst` | Dock LED pin constraints; JTAG pads connect internally |
| `jtag/board.cfg` | OpenOCD USB-JTAG adapter and TAP configuration |
| `jtag/host.tcl` | PC exchange command and hardware test |

All mailbox state runs in the JTAG TCK domain, so no clock-domain crossing is needed. An explicit global clock buffer distributes TCK. On this device, the primitive's `test_logic_reset_o` output is active low despite its name.

The normal configuration TAP remains available: this example does **not** repurpose JTAG pins as GPIO. `GW_JTAG` and its user instructions are described in [JTAG on the Tang Nano 20k](https://retroramblings.net/?p=2042); the board pin assignments follow [Apicula's Primer 20K constraints](https://github.com/YosysHQ/apicula/blob/master/examples/primer20k.cst).

### Hardware verification

The on-board test passed **38 requests** at both **3 MHz and 6 MHz JTAG**: zero, all ones, a mixed word, the top bit, alternating-bit patterns, and all 32 walking-one patterns. Every response and count increment matched, and every repeated read preserved the result and count. The all-ones request verified wraparound to zero. SRAM programming also succeeded at the board's default 6 MHz, followed by a passing mailbox test. The mailbox place-and-route timing target is 6 MHz.

The single-word command shown above was also exercised separately. Generated Verilog, bitstreams, and build logs are under `build/`, which is ignored by Git.

## USB-JTAG troubleshooting

Programming uses openFPGALoader's board-default **6 MHz** JTAG clock, and OpenOCD mailbox communication is configured for **6 MHz**. The initial 1 MHz setting was conservative, not a demonstrated requirement: after correcting the board-enable state, programming and communication passed at 6 MHz.

During initial bring-up, the debugger sometimes stalled or reported USB bulk-transfer errors, including during verbose programming. Unplugging and reconnecting USB-JTAG recovered it; a software USB reset did not always suffice. Those failures do not establish a clock-rate limit.

If SRAM erase stalls, check the board-enable switch and power-cycle the board. If USB errors persist, unplug/reconnect the debugger before retrying. After a power cycle, reload the desired SRAM example before testing it.
