# Tang Primer 20K Bluespec JTAG mailbox.
# Programming uses the board-default 6 MHz JTAG clock and writes SRAM only.
# Older Dock boards require DIP1 down/ON to enable the FPGA.
.PHONY: all detect

all: build/jtag.fs

build:
	mkdir -p $@

detect:
	openFPGALoader -b tangprimer20k --detect

# Bluespec mailbox over the hard JTAG user registers (not the UART).
# make jtag: build; make program-jtag: load SRAM; make test-jtag: hardware test.
# make exchange-jtag WORD=0x12345678: send one word and check word+1.
# Requires bsc, Yosys, nextpnr-himbaechel, Apicula and openFPGALoader.
# PC exchange commands additionally require OpenOCD.
# Run program-jtag before test-jtag/exchange-jtag; both host commands use JTAG,
# never the UART, and verify the mailbox signature, result and write count.
# ER1/IR 0x42 writes 32 bits; ER2/IR 0x43 reads 96 bits, LSB first:
# [31:0] = word+1 (mod 2^32), [63:32] = write count, [95:64] = 0x4a544147.
# Dock LEDs display the low six result bits. TAP reset clears the mailbox.
# Verified on the connected board: 38 commands plus stable repeated reads.
# All programming targets are SRAM-only; power cycling restores the flash image.
.PHONY: jtag program-jtag test-jtag exchange-jtag

jtag: build/jtag.fs

build/bsv: | build
	mkdir -p $@

build/bsv/mkJtagMailbox.v: jtag/JtagMailbox.bsv | build/bsv
	bsc -u -verilog -g mkJtagMailbox -bdir build/bsv -vdir build/bsv -info-dir build/bsv $<

build/jtag-synth.json: jtag/top.v build/bsv/mkJtagMailbox.v
	yosys -Q -l build/jtag-synthesis.log -p 'read_verilog jtag/top.v build/bsv/mkJtagMailbox.v; synth_gowin -top jtag_top -family gw2a -json $@'

# GW_JTAG routing/fuse support is in the GW2A-18C database.
build/jtag-routed.json: build/jtag-synth.json jtag/primer20k.cst
	nextpnr-himbaechel --device GW2A-LV18PG256C8/I7 -o family=GW2A-18C -o cst=jtag/primer20k.cst --freq 6 --json $< --write $@ --log build/jtag-nextpnr.log

build/jtag.fs: build/jtag-routed.json
	gowin_pack -d GW2A-18C -o $@ $<

program-jtag: build/jtag.fs
	openFPGALoader -b tangprimer20k --write-sram $<

test-jtag:
	openocd -f jtag/board.cfg -f jtag/host.tcl

exchange-jtag:
	JTAG_WORD=$(WORD) openocd -f jtag/board.cfg -f jtag/host.tcl
