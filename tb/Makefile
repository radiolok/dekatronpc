# Cocotb Makefile for DekatronPC UVM test infrastructure
# Supports both Icarus Verilog and Verilator backends
#
# Usage:
#   make test_compare SIM=icarus     - run a specific test
#   make SIM=icarus                  - run the test specified by MODULE/TOPLEVEL env
#   make clean                       - remove build artifacts
#
# Set MODULE, TOPLEVEL, VERILOG_SOURCES before running, or use the convenience targets.
# For Verilator: make SIM=verilator TOPLEVEL=... ...

VHDL_ROOT = $(realpath $(CURDIR)/../rtl)

# --- Simulator selection ---
SIM ?= icarus
TOPLEVEL_LANG ?= verilog

# --- Cocotb settings ---
export COCOTB_ANSI_OUTPUT = 1
export COCOTB_REDUCED_LOG_FMT = 1
export COCOTB_RESOLVE_X = ZEROS
export COCOTB_HDL_TIMEUNIT = 1ns
export COCOTB_HDL_TIMEPRECISION = 1ps

# --- Icarus-specific ---
# --- Verilator-specific ---
ifeq ($(SIM), verilator)
    EXTRA_ARGS += --timing -Wno-fatal
    VERILATOR_TRACE ?= 0
    ifeq ($(VERILATOR_TRACE),1)
        EXTRA_ARGS += --trace
    endif
endif

# --- Source file short-hands ---
# DPC.files and Emul.files use paths relative to vhdl/DekatronPC/ (all start with ../)
# Since iverilog resolves -f file paths relative to CWD, we expand to absolute paths
DPC_FILE_CONTENT = $(shell sed 's|^\.\./|$(VHDL_ROOT)/|' $(VHDL_ROOT)/DekatronPC/DPC.files)
EMUL_FILE_CONTENT = $(shell sed 's|^\.\./|$(VHDL_ROOT)/|' $(VHDL_ROOT)/Emulator/Emul.files)
DPC_SOURCES = $(DPC_FILE_CONTENT)
DPC_SOURCES_EMUL = $(DPC_FILE_CONTENT)
EMUL_SOURCES = $(DPC_FILE_CONTENT) $(EMUL_FILE_CONTENT)

LOGIC_PATH = $(VHDL_ROOT)/Logic
DEKATRON_PATH = $(VHDL_ROOT)/DekatronPC/Dekatron
DPC_PATH = $(VHDL_ROOT)/DekatronPC
FUNC_PATH = $(VHDL_ROOT)/Functions
EMUL_PATH = $(VHDL_ROOT)/Emulator

# =====================================================================
# Convenience targets for each test module
# =====================================================================

# --- Phase 1: Logic Primitives ---
test_compare:          MODULE = tests.test_compare
test_compare:          TOPLEVEL = Compare
test_compare:          VERILOG_SOURCES = $(LOGIC_PATH)/Compare.sv
test_compare:          sim

test_impulse:          MODULE = tests.test_impulse
test_impulse:          TOPLEVEL = Impulse_test_wrapper
test_impulse:          VERILOG_SOURCES = $(LOGIC_PATH)/Impulse.sv $(CURDIR)/tests/Impulse_wrapper.sv
test_impulse:          sim

test_oneshot:          MODULE = tests.test_oneshot
test_oneshot:          TOPLEVEL = OneShot_test_wrapper
test_oneshot:          VERILOG_SOURCES = $(LOGIC_PATH)/OneShot.sv $(CURDIR)/tests/OneShot_wrapper.sv
test_oneshot:          sim

test_rs_latch:         MODULE = tests.test_rs_latch
test_rs_latch:         TOPLEVEL = RsLatch
test_rs_latch:         VERILOG_SOURCES = $(LOGIC_PATH)/RsLatch.sv
test_rs_latch:         sim

test_clock_divider:    MODULE = tests.test_clock_divider
test_clock_divider:    TOPLEVEL = ClockDivider
test_clock_divider:    VERILOG_SOURCES = $(LOGIC_PATH)/ClockDivider.sv
test_clock_divider:    sim

test_bcd_counter:      MODULE = tests.test_bcd_counter
test_bcd_counter:      TOPLEVEL = BCDCounterX1
test_bcd_counter:      VERILOG_SOURCES = $(LOGIC_PATH)/BCDCounter.sv
test_bcd_counter:      sim

test_up_counter:       MODULE = tests.test_up_counter
test_up_counter:       TOPLEVEL = UpCounter
test_up_counter:       VERILOG_SOURCES = $(LOGIC_PATH)/UpCounter.sv
test_up_counter:       sim

# --- Phase 2: Dekatron Subsystem ---
test_bcd_to_bin:       MODULE = tests.test_dekatron_modules
test_bcd_to_bin:       TOPLEVEL = BcdToBin
test_bcd_to_bin:       VERILOG_SOURCES = $(DEKATRON_PATH)/BcdToBin.v
test_bcd_to_bin:       sim

test_bin_to_bcd:       MODULE = tests.test_dekatron_modules
test_bin_to_bcd:       TOPLEVEL = BinToBcd
test_bin_to_bcd:       VERILOG_SOURCES = $(DEKATRON_PATH)/BinToBcd.v
test_bin_to_bcd:       sim

test_dek_carry:        MODULE = tests.test_dekatron_carry
test_dek_carry:        TOPLEVEL = DekatronCarrySignal
test_dek_carry:        VERILOG_SOURCES = $(LOGIC_PATH)/RsLatch.sv $(DEKATRON_PATH)/DekatronCarrySignal.sv
test_dek_carry:        sim

test_pulse_sender:     MODULE = tests.test_dekatron_pulse
test_pulse_sender:     TOPLEVEL = DekatronPulseSender
test_pulse_sender:     VERILOG_SOURCES = $(LOGIC_PATH)/Impulse.sv $(LOGIC_PATH)/OneShot.sv $(DEKATRON_PATH)/DekatronPulseSender.sv
test_pulse_sender:     sim

test_write_amp:        MODULE = tests.test_dekatron_modules
test_write_amp:        TOPLEVEL = DekatronWriteAmp
test_write_amp:        VERILOG_SOURCES = $(DEKATRON_PATH)/DekatronWriteAmp.sv
test_write_amp:        sim

test_dekatron_unit:    MODULE = tests.test_dekatron_unit
test_dekatron_unit:    TOPLEVEL = Dekatron
test_dekatron_unit:    VERILOG_SOURCES = $(DEKATRON_PATH)/Dekatron.sv
test_dekatron_unit:    sim

test_dekatron_module:  MODULE = tests.test_dekatron_module
test_dekatron_module:  TOPLEVEL = DekatronModule
test_dekatron_module:  VERILOG_SOURCES = $(LOGIC_PATH)/Impulse.sv $(LOGIC_PATH)/OneShot.sv $(DEKATRON_PATH)/BcdToBin.v $(DEKATRON_PATH)/BinToBcd.v $(DEKATRON_PATH)/Dekatron.sv $(DEKATRON_PATH)/DekatronPulseSender.sv $(DEKATRON_PATH)/DekatronCarrySignal.sv $(LOGIC_PATH)/RsLatch.sv $(DEKATRON_PATH)/DekatronWriteAmp.sv $(DEKATRON_PATH)/DekatronModule.sv
test_dekatron_module:  sim

test_dek_counter:      MODULE = tests.test_dekatron_counter
test_dek_counter:      TOPLEVEL = DekatronCounter
test_dek_counter:      VERILOG_SOURCES = $(VHDL_ROOT)/parameters.sv $(LOGIC_PATH)/Compare.sv $(LOGIC_PATH)/Impulse.sv $(LOGIC_PATH)/OneShot.sv $(DEKATRON_PATH)/BcdToBin.v $(DEKATRON_PATH)/BinToBcd.v $(DEKATRON_PATH)/Dekatron.sv $(DEKATRON_PATH)/DekatronPulseSender.sv $(DEKATRON_PATH)/DekatronCarrySignal.sv $(LOGIC_PATH)/RsLatch.sv $(DEKATRON_PATH)/DekatronWriteAmp.sv $(DEKATRON_PATH)/DekatronModule.sv $(DEKATRON_PATH)/DekatronCounter.sv $(LOGIC_PATH)/ClockDivider.sv $(FUNC_PATH)/BcdToBinEnc.sv
test_dek_counter:      sim

# --- Phase 3: Memory Subsystem ---
test_ram:              MODULE = tests.test_ram
test_ram:              TOPLEVEL = RAM
test_ram:              VERILOG_SOURCES = $(DPC_PATH)/RAM.sv $(VHDL_ROOT)/parameters.sv
test_ram:              sim

test_ip_memory:        MODULE = tests.test_ip_memory
test_ip_memory:        TOPLEVEL = IpMemory
test_ip_memory:        VERILOG_SOURCES = $(VHDL_ROOT)/parameters.sv $(LOGIC_PATH)/Impulse.sv $(LOGIC_PATH)/OneShot.sv $(FUNC_PATH)/BcdToBinEnc.sv $(VHDL_ROOT)/programs/bootloader/bootloader.sv $(DPC_PATH)/IpMemory.sv
test_ip_memory:        sim

test_rom:              MODULE = tests.test_rom
test_rom:              TOPLEVEL = ROM
test_rom:              VERILOG_SOURCES = $(VHDL_ROOT)/parameters.sv $(DPC_PATH)/ROM.sv $(VHDL_ROOT)/programs/firmware.sv
test_rom:              sim

# --- Phase 4: DPC Core ---
test_loop_detect:      MODULE = tests.test_insn_loop_detect
test_loop_detect:      TOPLEVEL = InsnLoopDetector
test_loop_detect:      VERILOG_SOURCES = $(VHDL_ROOT)/parameters.sv $(DPC_PATH)/InsnLoopDetector.sv
test_loop_detect:      sim

test_insn_decoder:     MODULE = tests.test_insn_decoder
test_insn_decoder:     TOPLEVEL = InsnDecoder
test_insn_decoder:     VERILOG_SOURCES = $(VHDL_ROOT)/parameters.sv $(DPC_PATH)/InsnDecoder.sv
test_insn_decoder:     sim

test_ap_line:          MODULE = tests.test_ap_line
test_ap_line:          TOPLEVEL = ApLine
test_ap_line:          VERILOG_SOURCES = $(DPC_SOURCES)
test_ap_line:          sim

test_ip_line:          MODULE = tests.test_ip_line
test_ip_line:          TOPLEVEL = IpLine
test_ip_line:          VERILOG_SOURCES = $(DPC_SOURCES)
test_ip_line:          sim

test_dpc:              MODULE = tests.test_dpc_integration
test_dpc:              TOPLEVEL = DekatronPC
test_dpc:              SIM = verilator
test_dpc:              VERILOG_SOURCES = $(DPC_SOURCES_EMUL)
test_dpc:              EXTRA_ARGS = --timing -Wno-fatal -DEMULATOR=1
test_dpc:              sim

# --- Phase 5: Emulator Peripherals ---
test_sequencer:        MODULE = tests.test_sequencer
test_sequencer:        TOPLEVEL = Sequencer
test_sequencer:        VERILOG_SOURCES = $(LOGIC_PATH)/Impulse.sv $(EMUL_PATH)/Sequencer.sv
test_sequencer:        sim

test_ms6205:           MODULE = tests.test_ms6205
test_ms6205:           TOPLEVEL = MS6205
test_ms6205:           VERILOG_SOURCES = $(VHDL_ROOT)/parameters.sv $(LOGIC_PATH)/Impulse.sv $(EMUL_PATH)/KeyboardKeys.sv $(FUNC_PATH)/OpcodeToSymbol.sv $(FUNC_PATH)/BinaryToHex.sv $(EMUL_PATH)/MS6205.sv
test_ms6205:           sim

test_keyboard:         MODULE = tests.test_keyboard
test_keyboard:         TOPLEVEL = Keyboard
test_keyboard:         VERILOG_SOURCES = $(VHDL_ROOT)/parameters.sv $(LOGIC_PATH)/Register.sv $(LOGIC_PATH)/RegisterFileFlatOut.sv $(EMUL_PATH)/KeyboardKeys.sv $(FUNC_PATH)/OpcodeToSymbol.sv $(FUNC_PATH)/BinaryToHex.sv $(EMUL_PATH)/Keyboard.sv
test_keyboard:         sim

test_io_register:      MODULE = tests.test_io_register
test_io_register:      TOPLEVEL = io_register_block
test_io_register:      VERILOG_SOURCES = $(LOGIC_PATH)/RegisterFileFlatOut.sv $(LOGIC_PATH)/Register.sv $(LOGIC_PATH)/RegisterFileSharedOut.sv $(LOGIC_PATH)/bn_mux_n_1_generate.sv $(EMUL_PATH)/input_regs.sv $(EMUL_PATH)/io_register_block.sv
test_io_register:      sim

test_uart:             MODULE = tests.test_uart
test_uart:             TOPLEVEL = uart_tx
test_uart:             VERILOG_SOURCES = $(VHDL_ROOT)/uart/uart_tx.sv
test_uart:             sim

test_uart_rx:          MODULE = tests.test_uart_rx
test_uart_rx:          TOPLEVEL = uart_rx
test_uart_rx:          VERILOG_SOURCES = $(VHDL_ROOT)/uart/uart_rx.sv
test_uart_rx:          sim

test_uart_loopback:    MODULE = tests.test_uart_loopback
test_uart_loopback:    TOPLEVEL = uart_loopback_wrapper
test_uart_loopback:    VERILOG_SOURCES = $(VHDL_ROOT)/uart/uart_tx.sv $(VHDL_ROOT)/uart/uart_rx.sv $(CURDIR)/tests/uart_loopback_wrapper.sv
test_uart_loopback:    sim

test_key_symbol:       MODULE = tests.test_key_symbol
test_key_symbol:       TOPLEVEL = KeyToSymbol
test_key_symbol:       VERILOG_SOURCES = $(FUNC_PATH)/OpcodeToSymbol.sv $(FUNC_PATH)/BinaryToHex.sv $(EMUL_PATH)/KeyToSymbol.sv
test_key_symbol:       sim

test_seg7:             MODULE = tests.test_seg7
test_seg7:             TOPLEVEL = segment7
test_seg7:             VERILOG_SOURCES = $(EMUL_PATH)/segment7.sv
test_seg7:             sim

# --- Phase 6: Conversion Functions ---
test_ascii_bcd:        MODULE = tests.test_conversions
test_ascii_bcd:        TOPLEVEL = AsciiToBcd
test_ascii_bcd:        VERILOG_SOURCES = $(FUNC_PATH)/AsciiToBcd.sv
test_ascii_bcd:        sim

test_bcd_ascii:        MODULE = tests.test_conversions
test_bcd_ascii:        TOPLEVEL = BcdToAscii
test_bcd_ascii:        VERILOG_SOURCES = $(FUNC_PATH)/BcdToAscii.sv
test_bcd_ascii:        sim

test_bcd_bin:          MODULE = tests.test_conversions
test_bcd_bin:          TOPLEVEL = BcdToBinEnc
test_bcd_bin:          VERILOG_SOURCES = $(FUNC_PATH)/BcdToBinEnc.sv
test_bcd_bin:          sim

test_bin_hex:          MODULE = tests.test_conversions
test_bin_hex:          TOPLEVEL = BinaryToHex_wrapper
test_bin_hex:          VERILOG_SOURCES = $(FUNC_PATH)/BinaryToHex.sv $(CURDIR)/tests/BinaryToHex_wrapper.sv
test_bin_hex:          sim

test_opcode_to_sym:    MODULE = tests.test_conversions
test_opcode_to_sym:    TOPLEVEL = OpcodeToSymbol_wrapper
test_opcode_to_sym:    VERILOG_SOURCES = $(FUNC_PATH)/OpcodeToSymbol.sv $(CURDIR)/tests/OpcodeToSymbol_wrapper.sv
test_opcode_to_sym:    sim

test_sym_to_opcode:    MODULE = tests.test_conversions
test_sym_to_opcode:    TOPLEVEL = SymbolToOpcode_wrapper
test_sym_to_opcode:    VERILOG_SOURCES = $(FUNC_PATH)/SymbolToOpcode.sv $(CURDIR)/tests/SymbolToOpcode_wrapper.sv
test_sym_to_opcode:    sim

test_in12:             MODULE = tests.test_conversions
test_in12:             TOPLEVEL = In12CathodeToPin_wrapper
test_in12:             VERILOG_SOURCES = $(FUNC_PATH)/In12CathodeToPin.sv $(CURDIR)/tests/In12CathodeToPin_wrapper.sv
test_in12:             sim

# =====================================================================
# Core simulation target
# =====================================================================
sim:
	COCOTB_HDL_TIMEUNIT=1ns COCOTB_HDL_TIMEPRECISION=1ps \
	$(MAKE) TOPLEVEL=$(TOPLEVEL) TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		SIM=$(SIM) MODULE=$(MODULE) \
		VERILOG_SOURCES="$(VERILOG_SOURCES)" \
		EXTRA_ARGS="$(EXTRA_ARGS)" \
		-f $(shell cocotb-config --makefile)/Makefile.sim

# =====================================================================
# Pytest-based regression runner with coverage summary
# =====================================================================
regression:
	@echo "=== DekatronPC UVM Regression ==="
	@echo ""
	@echo "Generating firmware ROM..."
	@python3 $(VHDL_ROOT)/run/generate_rom.py -f $(VHDL_ROOT)/programs/looptest.bfk -o $(VHDL_ROOT)/programs/firmware.sv
	@echo "Generating zeros.txt..."
	@python3 -c "open('zeros.txt','w').write('\n'.join(['00']*30000))"
	@python3 -c "open('$(VHDL_ROOT)/zeros.txt','w').write('\n'.join(['00']*30000))"
	@TMPFILE=$$(mktemp /tmp/dek_regress.XXXXXX); \
	MODULES="Logic:compare impulse oneshot rs_latch bcd_counter up_counter clock_divider \
	         Dekatron:bcd_to_bin bin_to_bcd dek_carry pulse_sender dekatron_unit dek_counter \
	         Memory:ram ip_memory rom \
	         DPC:loop_detect insn_decoder \
	         Emulator:sequencer ms6205 keyboard io_register uart uart_rx uart_loopback key_symbol seg7 \
	         Functions:ascii_bcd bcd_ascii bcd_bin bin_hex opcode_to_sym sym_to_opcode in12"; \
	for group in $$MODULES; do \
	    grp=$${group%%:*}; \
	    tests=$${group##*:}; \
	    for t in $$tests; do \
	        rm -rf sim_build; \
	        printf "  %-28s " "$$t:"; \
	        if make test_$$t SIM=icarus >/dev/null 2>&1; then \
	            echo "PASS"; \
	            echo "$$grp|$$t|PASS" >> $$TMPFILE; \
	        else \
	            echo "FAIL"; \
	            echo "$$grp|$$t|FAIL" >> $$TMPFILE; \
	        fi; \
	    done; \
	done; \
	echo ""; \
	echo "=================================="; \
	echo "  COVERAGE SUMMARY"; \
	echo "=================================="; \
	printf "  %-18s %7s %7s %7s %8s\n" "Module" "Tests" "Pass" "Fail" "Coverage"; \
	printf "  %-18s %7s %7s %7s %8s\n" "----------------" "------" "------" "------" "--------"; \
	TOTAL_TESTS=0; TOTAL_PASS=0; TOTAL_FAIL=0; \
	current_module=""; module_tests=0; module_pass=0; module_fail=0; \
	sorted_groups=$$(cut -d'|' -f1 $$TMPFILE | uniq); \
	for grp in $$sorted_groups; do \
	    tests=$$(grep "^$$grp|" $$TMPFILE | wc -l); \
	    pass=$$(grep "^$$grp|" $$TMPFILE | grep -c "PASS"); \
	    fail=$$(grep "^$$grp|" $$TMPFILE | grep -c "FAIL"); \
	    pct=$$(( pass * 100 / (pass + fail) )); \
	    printf "  %-18s %7d %7d %7d %7d%%\n" "$$grp" "$$tests" "$$pass" "$$fail" "$$pct"; \
	    TOTAL_TESTS=$$((TOTAL_TESTS + tests)); \
	    TOTAL_PASS=$$((TOTAL_PASS + pass)); \
	    TOTAL_FAIL=$$((TOTAL_FAIL + fail)); \
	done; \
	printf "  %-18s %7s %7s %7s %8s\n" "----------------" "------" "------" "------" "--------"; \
	TOTAL_PCT=$$(( TOTAL_PASS * 100 / (TOTAL_PASS + TOTAL_FAIL) )); \
	printf "  %-18s %7d %7d %7d %7d%%\n" "TOTAL" "$$TOTAL_TESTS" "$$TOTAL_PASS" "$$TOTAL_FAIL" "$$TOTAL_PCT"; \
	echo ""; \
	rm -f $$TMPFILE; \
	if [ "$$TOTAL_FAIL" -gt 0 ]; then exit 1; fi

# =====================================================================
# Clean
# =====================================================================
clean::
	rm -rf __pycache__ sim_build results.xml *.vcd *.fst *.dat *.info
	find . -name '*.pyc' -delete
	find . -type d -name __pycache__ -delete
	find . -type d -name sim_build -exec rm -rf {} + 2>/dev/null || true

.PHONY: clean regression sim
