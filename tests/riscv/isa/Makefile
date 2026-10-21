include ../common.mk

# ISA suites share simulator stamps, object directories, and published paths.
.NOTPARALLEL:

# Upstream RISC-V ISA tests (riscv-tests/isa). The upstream tree is cloned
# and built by the $(RISCV_TESTS_STAMP) rule in ../common.mk; the run-*
# targets below depend on it, so the first invocation auto-installs.
#
# These tests run unmodified — Vortex's synchronous trap path (ECALL ->
# mtvec) lets the test's own trap_vector run, and the HTIF `tohost`
# watcher in the simulators harvests pass/fail.

# Generated headers also emit helper functions, so preprocessor output is not a scalar flag.
ISA_CONFIGS := $(shell python3 $(ROOT_DIR)/ci/gen_config.py --config=$(VORTEX_HOME)/VX_config.toml --cflags='$(CONFIGS) -DVX_CFG_XLEN=$(XLEN)')
ifneq ($(.SHELLSTATUS),0)
$(error could not resolve ISA configuration)
endif
HAS_EXT_A := $(filter -DVX_CFG_EXT_A_ENABLED=1,$(ISA_CONFIGS))
HAS_EXT_C := $(filter -DVX_CFG_EXT_C_ENABLED=1,$(ISA_CONFIGS))

# Test-suite prefixes (extension-gated). A/C are only run when the build
# was configured with the corresponding extension.
P_32I := rv32ui-p
P_32M := rv32um-p
P_32F := rv32uf-p
P_32D := rv32ud-p
P_32A :=
P_32C :=
P_64I := rv64ui-p
P_64M := rv64um-p
P_64F := rv64uf-p
P_64D := rv64ud-p
P_64A :=
P_64C :=
ifneq ($(HAS_EXT_A),)
P_32A := rv32ua-p
P_64A := rv64ua-p
endif
ifneq ($(HAS_EXT_C),)
P_32C := rv32uc-p
P_64C := rv64uc-p
endif

# Run one or more test-suite prefixes against a simulator.
#   $(1) = simulator (simx | rtlsim)
#   $(2) = space-separated test prefixes (e.g. "rv32ui-p rv32um-p")
# Known-unsupported tests are skipped: fence_i (no instruction-cache
# coherence), ma_data (no misaligned-access trap), rv64uc-p-rvc
# (misaligned C.FLD the upstream test expects to trap on).
define run_isa
$(if $(strip $(2)),,$(error $@ requires an enabled ISA extension in CONFIGS))
$(if $(filter rtlsim,$(1)),+@$(MAKE) -C $(SIM_DIR)/rtlsim)
@set -e; for pfx in $(2); do found=0; for t in $(ISA_DIR)/$$pfx-*; do \
  case "$$t" in *.dump) continue;; esac; [ -f "$$t" ] || continue; \
  found=1; \
  b=`basename $$t`; \
  case "$$b" in *-fence_i|*-ma_data|rv64uc-p-rvc) echo "[skip] $$b"; continue;; esac; \
  echo "[run]  $$b"; $(SIM_DIR)/$(1)/$(1) "$$t" || { echo "[FAIL] $$b"; exit 1; }; \
done; [ $$found -eq 1 ] || { echo "[FAIL] no ISA binaries for $$pfx" >&2; exit 1; }; \
done; echo "[$(1)] passed: $(2)"
endef

all:

run-simx-32imf: $(RISCV_TESTS_STAMP)
	$(call run_isa,simx,$(P_32I) $(P_32M) $(P_32F))

run-simx-64imf: $(RISCV_TESTS_STAMP)
	$(call run_isa,simx,$(P_64I) $(P_64M) $(P_64F))

run-simx-32imafd: $(RISCV_TESTS_STAMP)
	$(call run_isa,simx,$(P_32I) $(P_32M) $(P_32F) $(P_32D) $(P_32A) $(P_32C))

run-simx-64imafd: $(RISCV_TESTS_STAMP)
	$(call run_isa,simx,$(P_64I) $(P_64M) $(P_64F) $(P_64D) $(P_64A) $(P_64C))

run-simx-32i: $(RISCV_TESTS_STAMP)
	$(call run_isa,simx,$(P_32I))

run-simx-32im: $(RISCV_TESTS_STAMP)
	$(call run_isa,simx,$(P_32I) $(P_32M))

run-simx-32f: $(RISCV_TESTS_STAMP)
	$(call run_isa,simx,$(P_32F))

run-simx-32d: $(RISCV_TESTS_STAMP)
	$(call run_isa,simx,$(P_32D))

run-simx-32a: $(RISCV_TESTS_STAMP)
	$(call run_isa,simx,$(P_32A))

run-simx-32c: $(RISCV_TESTS_STAMP)
	$(call run_isa,simx,$(P_32C))

run-simx-64im: $(RISCV_TESTS_STAMP)
	$(call run_isa,simx,$(P_64I) $(P_64M))

run-simx-64f: $(RISCV_TESTS_STAMP)
	$(call run_isa,simx,$(P_64F))

run-simx-64d: $(RISCV_TESTS_STAMP)
	$(call run_isa,simx,$(P_64D))

run-simx-64a: $(RISCV_TESTS_STAMP)
	$(call run_isa,simx,$(P_64A))

run-simx-64c: $(RISCV_TESTS_STAMP)
	$(call run_isa,simx,$(P_64C))

run-simx-32: run-simx-32imafd

run-simx-64: run-simx-32imafd run-simx-64imafd

run-simx: run-simx-$(XLEN)

run-rtlsim-32imf: $(RISCV_TESTS_STAMP)
	$(call run_isa,rtlsim,$(P_32I) $(P_32M) $(P_32F))

run-rtlsim-64imf: $(RISCV_TESTS_STAMP)
	$(call run_isa,rtlsim,$(P_64I) $(P_64M) $(P_64F))

run-rtlsim-32i: $(RISCV_TESTS_STAMP)
	$(call run_isa,rtlsim,$(P_32I))

run-rtlsim-32im: $(RISCV_TESTS_STAMP)
	$(call run_isa,rtlsim,$(P_32I) $(P_32M))

run-rtlsim-32f: $(RISCV_TESTS_STAMP)
	$(call run_isa,rtlsim,$(P_32F))

run-rtlsim-32a: $(RISCV_TESTS_STAMP)
	$(call run_isa,rtlsim,$(P_32A))

run-rtlsim-32c: $(RISCV_TESTS_STAMP)
	$(call run_isa,rtlsim,$(P_32C))

run-rtlsim-64im: $(RISCV_TESTS_STAMP)
	$(call run_isa,rtlsim,$(P_64I) $(P_64M))

run-rtlsim-64f: $(RISCV_TESTS_STAMP)
	$(call run_isa,rtlsim,$(P_64F))

run-rtlsim-64d: $(RISCV_TESTS_STAMP)
	$(call run_isa,rtlsim,$(P_64D))

run-rtlsim-64a: $(RISCV_TESTS_STAMP)
	$(call run_isa,rtlsim,$(P_64A))

run-rtlsim-64c: $(RISCV_TESTS_STAMP)
	$(call run_isa,rtlsim,$(P_64C))

run-rtlsim-32: run-rtlsim-32imf

run-rtlsim-64: run-rtlsim-32imf run-rtlsim-64imf

run-rtlsim: run-rtlsim-$(XLEN)

clean:

.PHONY: all clean \
        run-simx run-simx-32 run-simx-64 run-rtlsim run-rtlsim-32 run-rtlsim-64
