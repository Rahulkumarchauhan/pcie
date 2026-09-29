##############################################################
# Free (no licence) smoke test of the SVA assertions.
#   make          build + run every case
#   make legal    only the legal-stimulus run (must be silent)
#   make clean
# Needs verilator on the PATH (https://www.verilator.org).
##############################################################

VERILATOR ?= verilator
TOP        = tb_sva
SVA        = ../pcie5_phy_assertions.sv
SOURCES    = sva_stub_dut.sv $(SVA) tb_sva.sv
BUILD_DIR  = obj_dir
SIM        = $(BUILD_DIR)/V$(TOP)

INJECTIONS = A01_tlp_end_only A02_dllp_end_only A03_gen_bad \
             A05_sub_mismatch A06_link_stuck A07_powerdown_bad \
             A08_sync_bad A09_rxvalid_bad A10_cfg_change A04_linkup_in_reset

all: build legal injections
	@echo "== all SVA smoke tests finished =="

build:
	$(VERILATOR) --binary --assert -Wno-fatal --timing --top-module $(TOP) $(SOURCES)

legal: build
	@echo "== legal stimulus (expect no failure) =="
	@$(SIM) +MODE=legal | tail -n 3

injections: build
	@echo "== injected violations (each must fire its own assertion) =="
	@for inj in $(INJECTIONS); do \
	  out=$$($(SIM) +MODE=inj +INJ=$$inj 2>&1); \
	  hit=$$(echo "$$out" | grep -oE "a[0-9]{2}_[a-z0-9_]+" | head -1); \
	  if echo "$$out" | grep -q "Assertion failed"; then \
	    printf "%-22s -> FIRED  %s\n" "$$inj" "$$hit"; \
	  else \
	    printf "%-22s -> NOT DETECTED\n" "$$inj"; \
	  fi; \
	done

clean:
	rm -rf $(BUILD_DIR)
