# RTL-to-GDSII RISC-V project
SHELL := /bin/bash
RTL   := $(wildcard rtl/*.v)

.PHONY: all sim waves synth lint hex openlane clean
all: sim synth

hex: sw/test.hex
sw/test.hex: sw/test.S sw/asm.py
	python3 sw/asm.py sw/test.S sw/test.hex

sim: hex
	@mkdir -p sim
	iverilog -g2005 -DSIM -o sim/tb.vvp tb/tb_rv32_core.v $(RTL)
	vvp sim/tb.vvp | tee sim/sim.log
	@grep -q "\[TB\] PASS" sim/sim.log

waves: hex
	@mkdir -p sim
	iverilog -g2005 -DSIM -DVCD -o sim/tb.vvp tb/tb_rv32_core.v $(RTL)
	vvp sim/tb.vvp && gtkwave sim/tb_rv32_core.vcd &

lint:
	iverilog -g2005 -Wall -o /dev/null $(RTL)

# Quick technology-independent synthesis sanity check (no PDK needed)
synth:
	yosys -q -p "read_verilog $(RTL); hierarchy -top rv32_core; synth -flatten -top rv32_core; check -assert; tee -o sim/synth_stat.txt stat"
	@grep -E "Number of cells" sim/synth_stat.txt | head -1

# Full RTL-to-GDSII (needs OpenLane 2 + sky130A PDK; see README)
openlane:
	cd openlane && openlane --dockerized config.json

clean:
	rm -rf sim openlane/runs
