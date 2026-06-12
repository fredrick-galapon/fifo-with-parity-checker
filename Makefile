# directories
RTL_DIR   	= rtl
SIM_DIR   	= sim
PNR_DIR   	= librelane
FINAL_DIR 	= final
LIB_DIR   	= lib
SCRIPT_DIR	= scripts
BUILD_DIR 	= build

# sources
RTL_SRC     ?= $(wildcard $(RTL_DIR)/*.v)
TOP         ?= top
TB          = tb_$(TOP)

# targets
.PHONY: help all sim pnr pls wave wave_pls clean

help:
	@echo ""
	@echo "  make sim         perform RTL simulation in Icarus Verilog"
	@echo "  make pnr         run PNR in LibreLane"
	@echo "  make pls         run post-layout simulation in CVC"
	@echo "  make wave        view RTL waveform in GTKWave"
	@echo "  make wave_pls    view PLS waveform in GTKWave"
	@echo "  make clean       remove build artifacts"
	@echo ""

all: sim pnr pls

# build directory
$(BUILD_DIR):
	mkdir -p $@

# RTL simulation
sim: $(BUILD_DIR)/sim-$(TB).log

$(BUILD_DIR)/sim-$(TB).log: $(SIM_DIR)/$(TB).v $(RTL_SRC) | $(BUILD_DIR)
	TB=$(TB) RTL_DIR=$(RTL_DIR) BUILD_DIR=$(BUILD_DIR) \
		bash $(SCRIPT_DIR)/run_iverilog.sh 2>&1 | tee $@
	@(! grep -i "error" $@) || (echo "ERRORS found in $@"; exit 1)

# synthesis & PNR
pnr: $(BUILD_DIR)/pnr.log

$(BUILD_DIR)/pnr.log: $(PNR_DIR)/config.json $(RTL_SRC) | $(BUILD_DIR)
	PNR_DIR=$(PNR_DIR) \
		bash $(SCRIPT_DIR)/run_librelane.sh 2>&1 | tee $@
	@(! grep -i "LibreLane will now quit" $@) || (echo "ERRORS found in $@"; exit 1)

# post-layout simulation
pls: $(BUILD_DIR)/pls.log

# $(BUILD_DIR)/pls.log: $(SIM_DIR)/$(TB).v $(FINAL_DIR)/$(TOP).pnl.v | $(BUILD_DIR)
# 	TB=$(TB) FINAL_DIR=$(FINAL_DIR) RTL_DIR=$(RTL_DIR) \
# 		LIB_DIR=$(LIB_DIR) SCRIPTS_DIR=$(SCRIPT_DIR) BUILD_DIR=$(BUILD_DIR) \
# 		bash $(SCRIPT_DIR)/run_cvc.sh 2>&1 | tee $@
# 	@mv -f verilog.log $(BUILD_DIR)/
# 	@(! grep -i "Unable to begin simulation" $@) || (echo "ERRORS found in $@"; exit 1)

$(BUILD_DIR)/pls.log: $(SIM_DIR)/$(TB).v $(FINAL_DIR)/$(TOP).pnl.v | $(BUILD_DIR)
	TB=$(TB) FINAL_DIR=$(FINAL_DIR) RTL_DIR=$(RTL_DIR) \
		LIB_DIR=$(LIB_DIR) BUILD_DIR=$(BUILD_DIR) \
		bash $(SCRIPT_DIR)/run_iverilog_pls.sh 2>&1 | tee $@
	@(! grep -i "error" $@) || (echo "ERRORS found in $@"; exit 1)

# waveform viewer
wave: $(BUILD_DIR)/$(TB).vcd
	gtkwave $< &

wave_pls: $(BUILD_DIR)/$(TB)_pls.vcd
	gtkwave $< &

# clean
clean:
	rm -rf $(BUILD_DIR)