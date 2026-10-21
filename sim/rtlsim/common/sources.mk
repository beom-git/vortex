CXXFLAGS += -std=c++17 -Wall -Wextra -Wfatal-errors -Werror
CXXFLAGS += -fPIC
# GCC 13 turns the generated per-word copy of a wide signal into a memcpy and
# inlines it with aligned 16-byte stores, faulting on a destination that is only
# 8-byte aligned in the root class (NUM_THREADS=16 + RTU crashes in reset).
CXXFLAGS += -fno-tree-loop-distribute-patterns
CXXFLAGS += -I$(SRC_DIR)/common -I$(ROOT_DIR)/sw -I$(ROOT_DIR)/hw -I$(SIM_COMMON_DIR) -I$(SW_COMMON_DIR)
CXXFLAGS += -I$(THIRD_PARTY_DIR)/softfloat/source/include
CXXFLAGS += -I$(THIRD_PARTY_DIR)/ramulator/ext/spdlog/include
CXXFLAGS += -I$(THIRD_PARTY_DIR)/ramulator/ext/yaml-cpp/include
CXXFLAGS += -I$(THIRD_PARTY_DIR)/ramulator/src
CXXFLAGS += -DVX_CFG_XLEN=$(XLEN) -DVX_CFG_XLEN_$(XLEN)
CXXFLAGS += $(CONFIGS)

LDFLAGS += $(THIRD_PARTY_DIR)/softfloat/build/Linux-x86_64-GCC/softfloat.a
LDFLAGS += -Wl,-rpath,$(THIRD_PARTY_DIR)/ramulator  -L$(THIRD_PARTY_DIR)/ramulator -lramulator -Wl,-rpath,$(THIRD_PARTY_DIR)/ramulator_ext -L$(THIRD_PARTY_DIR)/ramulator_ext -Wl,--push-state,--no-as-needed -lramulator-vortex -Wl,--pop-state

# control RTL debug tracing states
DBG_TRACE_FLAGS += -DDBG_TRACE_PIPELINE
DBG_TRACE_FLAGS += -DDBG_TRACE_MEM
DBG_TRACE_FLAGS += -DDBG_TRACE_CACHE
DBG_TRACE_FLAGS += -DDBG_TRACE_AFU
DBG_TRACE_FLAGS += -DDBG_TRACE_SCOPE
DBG_TRACE_FLAGS += -DDBG_TRACE_GBAR
DBG_TRACE_FLAGS += -DDBG_TRACE_TCU
DBG_TRACE_FLAGS += -DDBG_TRACE_RTU

# `override` so a command-line `make CONFIGS=...` cannot drop these mandatory flags.
override CONFIGS += -DSIMULATION -DSV_DPI

XCONFIGS := $(shell python3 $(VORTEX_HOME)/ci/gen_config.py --config=$(VORTEX_HOME)/VX_config.toml --cflags='$(CONFIGS) -DVX_CFG_XLEN=$(XLEN)')

DBG_FLAGS += -DVX_DBG_DEBUG_LEVEL=$(DEBUG) $(DBG_TRACE_FLAGS)
RTL_PKGS = $(RTL_DIR)/VX_gpu_pkg.sv $(RTL_DIR)/fpu/VX_fpu_pkg.sv

FPU_INCLUDE = -I$(RTL_DIR)/fpu
ifneq (,$(filter -DVX_CFG_FPU_TYPE_FPNEW -DVX_CFG_TCU_TYPE_FPNEW, $(XCONFIGS)))
	# fpu_div_sqrt_mvp/hdl/*.sv must be passed explicitly (not auto-
	# discovered via -I/-y) so the file-scope `import defs_div_sqrt_mvp::*;`
	# in control_mvp.sv resolves. Verilator parses auto-discovered files
	# in a separate scope where the file-scope import cannot see the
	# explicitly-listed defs_div_sqrt_mvp package.
	RTL_PKGS += $(THIRD_PARTY_DIR)/cvfpu/src/fpnew_pkg.sv \
	            $(THIRD_PARTY_DIR)/cvfpu/src/common_cells/src/cf_math_pkg.sv \
	            $(THIRD_PARTY_DIR)/cvfpu/src/fpu_div_sqrt_mvp/hdl/defs_div_sqrt_mvp.sv
	RTL_PRE_SRCS += $(THIRD_PARTY_DIR)/cvfpu/src/fpu_div_sqrt_mvp/hdl/control_mvp.sv \
	            $(THIRD_PARTY_DIR)/cvfpu/src/fpu_div_sqrt_mvp/hdl/iteration_div_sqrt_mvp.sv \
	            $(THIRD_PARTY_DIR)/cvfpu/src/fpu_div_sqrt_mvp/hdl/norm_div_sqrt_mvp.sv \
	            $(THIRD_PARTY_DIR)/cvfpu/src/fpu_div_sqrt_mvp/hdl/nrbd_nrsc_mvp.sv \
	            $(THIRD_PARTY_DIR)/cvfpu/src/fpu_div_sqrt_mvp/hdl/preprocess_mvp.sv \
	            $(THIRD_PARTY_DIR)/cvfpu/src/fpu_div_sqrt_mvp/hdl/div_sqrt_top_mvp.sv \
	            $(THIRD_PARTY_DIR)/cvfpu/src/fpu_div_sqrt_mvp/hdl/div_sqrt_mvp_wrapper.sv
	FPU_INCLUDE += -I$(THIRD_PARTY_DIR)/cvfpu/src/common_cells/include -I$(THIRD_PARTY_DIR)/cvfpu/src/common_cells/src -I$(THIRD_PARTY_DIR)/cvfpu/src
endif
RTL_INCLUDE = -I$(ROOT_DIR)/sw -I$(ROOT_DIR)/hw -I$(SRC_DIR)/common -I$(RTL_DIR) -I$(DPI_DIR) -I$(RTL_DIR)/libs -I$(RTL_DIR)/interfaces -I$(RTL_DIR)/core -I$(RTL_DIR)/mem -I$(RTL_DIR)/vm -I$(RTL_DIR)/cache $(FPU_INCLUDE)

# Add TCU extension sources
ifneq (,$(filter -DVX_CFG_EXT_TCU_ENABLE, $(XCONFIGS)))
	RTL_PKGS += $(RTL_DIR)/tcu/VX_tcu_pkg.sv
	RTL_INCLUDE += -I$(RTL_DIR)/tcu
	ifneq (,$(filter -DVX_CFG_TCU_TYPE_DPI, $(XCONFIGS)))
		RTL_INCLUDE += -I$(RTL_DIR)/tcu/dpi
	else ifneq (,$(filter -DVX_CFG_TCU_TYPE_DSP, $(XCONFIGS)))
		RTL_INCLUDE += -I$(RTL_DIR)/tcu/dsp
	else ifneq (,$(filter -DVX_CFG_TCU_TYPE_BHF, $(XCONFIGS)))
		RTL_INCLUDE += -I$(RTL_DIR)/tcu/bhf
		RTL_PRE_SRCS += $(THIRD_PARTY_DIR)/hardfloat/source/fNToRecFN.v
		RTL_PRE_SRCS += $(THIRD_PARTY_DIR)/hardfloat/source/addRecFN.v
		RTL_PRE_SRCS += $(THIRD_PARTY_DIR)/hardfloat/source/bsg_hardfloat_pkg.sv
		RTL_PRE_SRCS += $(THIRD_PARTY_DIR)/hardfloat/source/HardFloat_primitives.v
		RTL_PRE_SRCS += $(THIRD_PARTY_DIR)/hardfloat/source/HardFloat_rawFN.v
		RTL_PRE_SRCS += $(THIRD_PARTY_DIR)/hardfloat/source/isSigNaNRecFN.v
		RTL_PRE_SRCS += $(THIRD_PARTY_DIR)/hardfloat/source/mulRecFN.v
		RTL_PRE_SRCS += $(THIRD_PARTY_DIR)/hardfloat/source/recFNToFN.v
		RTL_PRE_SRCS += $(THIRD_PARTY_DIR)/hardfloat/source/recFNToRecFN.v
		RTL_INCLUDE += -I$(THIRD_PARTY_DIR)/hardfloat/source/RISCV
		RTL_INCLUDE += -I$(THIRD_PARTY_DIR)/hardfloat/source
	else ifneq (,$(filter -DVX_CFG_TCU_TYPE_FPNEW, $(XCONFIGS)))
		RTL_INCLUDE += -I$(RTL_DIR)/tcu/fpnew
		RTL_INCLUDE += -I$(THIRD_PARTY_DIR)/cvfpu/src/common_cells/include
		RTL_INCLUDE += -I$(THIRD_PARTY_DIR)/cvfpu/src/common_cells/src
		RTL_INCLUDE += -I$(THIRD_PARTY_DIR)/cvfpu/src
	else ifneq (,$(filter -DVX_CFG_TCU_TYPE_TFR, $(XCONFIGS)))
		RTL_INCLUDE += -I$(RTL_DIR)/tcu/tfr
	endif
endif

# Add DXA extension sources
ifneq (,$(filter -DVX_CFG_EXT_DXA_ENABLE, $(XCONFIGS)))
	RTL_PKGS += $(RTL_DIR)/dxa/VX_dxa_pkg.sv
	RTL_INCLUDE += -I$(RTL_DIR)/dxa
endif

# Add TEX extension sources
ifneq (,$(filter -DVX_CFG_EXT_TEX_ENABLE, $(XCONFIGS)))
	RTL_PKGS += $(RTL_DIR)/tex/VX_tex_pkg.sv
	RTL_INCLUDE += -I$(RTL_DIR)/tex
endif

# Add OM extension sources
ifneq (,$(filter -DVX_CFG_EXT_OM_ENABLE, $(XCONFIGS)))
	RTL_PKGS += $(RTL_DIR)/om/VX_om_pkg.sv
	RTL_INCLUDE += -I$(RTL_DIR)/om
endif

# Add RASTER extension sources
ifneq (,$(filter -DVX_CFG_EXT_RASTER_ENABLE, $(XCONFIGS)))
	RTL_PKGS += $(RTL_DIR)/raster/VX_raster_pkg.sv
	RTL_INCLUDE += -I$(RTL_DIR)/raster
endif

# Add RTU extension sources
ifneq (,$(filter -DVX_CFG_EXT_RTU_ENABLE, $(XCONFIGS)))
	RTL_PKGS += $(RTL_DIR)/rtu/VX_rtu_pkg.sv
	RTL_INCLUDE += -I$(RTL_DIR)/rtu
endif

RTL_PKGS += $(RTL_DIR)/VX_trace_pkg.sv $(RTL_DIR)/vm/VX_tlb_pkg.sv

SRCS = $(SW_COMMON_DIR)/util.cpp $(SIM_COMMON_DIR)/mem.cpp $(SW_COMMON_DIR)/softfloat_ext.cpp $(SW_COMMON_DIR)/rvfloats.cpp $(SIM_COMMON_DIR)/dram_sim.cpp $(SIM_COMMON_DIR)/elf_loader.cpp $(SIM_COMMON_DIR)/host_monitor.cpp $(SIM_COMMON_DIR)/cout_drainer.cpp
SRCS += $(DPI_DIR)/dpi_util.cpp $(DPI_DIR)/dpi_float.cpp
SRCS += $(SRC_DIR)/common/processor.cpp $(SRC_DIR)/common/bridge.cpp $(SRC_DIR)/common/dpi_bridge.cpp

# Scalar config values come from the included VX_config.vh; passing the full
# resolved XCONFIGS here would fight the header and break parameter constancy.
# Raw $(CONFIGS) carries only the enum *value* (e.g. VX_CFG_TCU_TYPE=DPI), which
# leaves the RTL `ifdef selectors (which key off the *companion*
# VX_CFG_TCU_TYPE_DPI) unmatched. Add just the enum companions gen_config
# resolves, so a CONFIGS enum override actually selects its RTL implementation.
RTL_DEFINES = -DVX_CFG_XLEN=$(XLEN) -DVX_CFG_XLEN_$(XLEN) $(CONFIGS) $(filter -DVX_CFG_TCU_TYPE_% -DVX_CFG_FPU_TYPE_%,$(XCONFIGS))
RTL_DIRS := $(patsubst -I%,%,$(filter -I%,$(RTL_INCLUDE)))
RTL_SRCS := $(shell find $(RTL_DIRS) -type d -name syn -prune -o -type f \( -name '*.v' -o -name '*.vh' -o -name '*.sv' -o -name '*.vi' \) -print)
