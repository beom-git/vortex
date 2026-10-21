ROOT_DIR := $(realpath ../..)
include $(ROOT_DIR)/config.mk

.DEFAULT_GOAL := all
SIMULATOR ?= verilator
ifneq ($(SIMULATOR),verilator)
ifneq ($(SIMULATOR),vcs)
$(error Unsupported SIMULATOR '$(SIMULATOR)'; choose verilator or vcs)
endif
endif

SRC_DIR = $(VORTEX_HOME)/sim/rtlsim
RTL_DIR = $(VORTEX_HOME)/hw/rtl
DPI_DIR = $(VORTEX_HOME)/hw/dpi
include $(ROOT_DIR)/sim/rtlsim/common/sources.mk

CXXFLAGS += $(XCONFIGS)
CXXFLAGS += -DNDEBUG
RTL_DEFINES += -DNDEBUG
RTL_INCLUDE := -I$(VORTEX_HOME)/tests/rtlsim $(RTL_INCLUDE)
SRCS += $(VORTEX_HOME)/tests/rtlsim/protocol.cpp
ENGINE_DIR := $(CURDIR)/.protocol/$(SIMULATOR)
CONFIG_FILE := $(ENGINE_DIR)/config.stamp
BUILD_INPUTS := $(ROOT_DIR)/config.mk $(wildcard $(ROOT_DIR)/sw/VX_*.h $(ROOT_DIR)/hw/VX_*.vh)
COMMON_HEADERS := $(wildcard $(SRC_DIR)/common/*.h $(SRC_DIR)/vcs/*.h $(SIM_COMMON_DIR)/*.h $(SW_COMMON_DIR)/*.h $(DPI_DIR)/*.vh)
THREADS ?= 4

ifeq ($(SIMULATOR),verilator)
VL_FLAGS = --exe --assert -Wall -Wpedantic
VL_FLAGS += -Wno-DECLFILENAME -Wno-REDEFMACRO
VL_FLAGS += $(RTL_DEFINES) $(RTL_INCLUDE)
VL_FLAGS += $(RTL_DIR)/VX_gpu_pkg.sv --cc testbench --top-module testbench -j $(THREADS) -MAKEFLAGS CXX=$(CXX) -MAKEFLAGS LINK=$(CXX)
SRCS += $(SRC_DIR)/verilator/engine.cpp $(SRC_DIR)/verilator/main.cpp
ENGINE_FLAGS = $(VL_FLAGS)
TOOL_VERSION = $(shell $(VERILATOR_PATH)/bin/verilator --version)
else ifeq ($(SIMULATOR),vcs)
CXXFLAGS += -I$(ENGINE_DIR)
VCS_FLAGS = -full64 -sverilog -assert enable_hier -timescale=1ns/1ps -j$(THREADS) -cpp $(CXX) -cc $(CC)
VCS_FLAGS += $(patsubst -D%,+define+%,$(RTL_DEFINES)) $(patsubst -I%,+incdir+%,$(RTL_INCLUDE))
VCS_FLAGS += $(RTL_DIR)/VX_gpu_pkg.sv $(SRC_DIR)/common/testbench.sv $(SRC_DIR)/vcs/top.sv -top vcs_top
VCS_FLAGS += $(foreach dir,$(patsubst -I%,%,$(RTL_INCLUDE)),-y $(dir)) +libext+.sv+.v
SRCS += $(SRC_DIR)/vcs/engine.cpp $(SRC_DIR)/vcs/runtime.cpp
ENGINE_FLAGS = $(VCS_FLAGS)
TOOL_VERSION = $(shell $(SIMULATOR) -ID 2>&1)
endif

.PHONY: all run clean force prepare prepare-protocol
all: protocol

prepare:
	@mkdir -p $(ENGINE_DIR)

prepare-protocol:
	@rm -f protocol

protocol: $(ENGINE_DIR)/protocol force
ifeq ($(SIMULATOR),verilator)
	ln -sfn $< $@
else ifeq ($(SIMULATOR),vcs)
	@printf '#!/bin/sh\nexec "%s" -exitstatus -assert finish_maxfail=1 +vcs+lic+wait "$$@"\n' '$<' > $@.tmp
	@chmod +x $@.tmp
	@mv -f $@.tmp $@
endif

$(ENGINE_DIR)/protocol: $(SRCS) $(RTL_SRCS) $(BUILD_INPUTS) $(COMMON_HEADERS) $(VORTEX_HOME)/tests/rtlsim/rtlsim_shim.sv $(SRC_DIR)/common/testbench.sv $(SRC_DIR)/vcs/top.sv $(CONFIG_FILE) $(VORTEX_HOME)/tests/rtlsim/Makefile | prepare-protocol
ifeq ($(SIMULATOR),verilator)
	MAKEFLAGS= $(VERILATOR_PATH)/bin/verilator --build $(VL_FLAGS) $(SRCS) -CFLAGS '$(CXXFLAGS)' -LDFLAGS '$(LDFLAGS)' --Mdir $(ENGINE_DIR)/obj_dir -o $@
else ifeq ($(SIMULATOR),vcs)
	cd $(ENGINE_DIR) && MAKEFILES='$(wildcard $(ENGINE_DIR)/obj_dir/*.d)' $(SIMULATOR) $(VCS_FLAGS) $(SRCS) -CFLAGS '$(CXXFLAGS)' -LDFLAGS '$(filter-out %.a,$(LDFLAGS))' -syslib '$(filter %.a,$(LDFLAGS))' -Mdir=obj_dir -o protocol
endif

$(CONFIG_FILE): force | prepare
	@printf '%s\n' "$(ENGINE_FLAGS)" "$(CXX) $(shell $(CXX) --version | head -1) $(CXXFLAGS)" "$(CC) $(shell $(CC) --version | head -1)" "$(LDFLAGS)" "$(TOOL_VERSION)" "$(SRCS) $(COMMON_HEADERS) $(RTL_SRCS)" > $@.tmp
	@if ! cmp -s $@.tmp $@; then mv $@.tmp $@; rm -rf $(ENGINE_DIR)/obj_dir; else rm -f $@.tmp; fi

run: protocol
ifeq ($(SIMULATOR),verilator)
	./protocol $(OPTS)
else ifeq ($(SIMULATOR),vcs)
	./protocol +program=$(if $(OPTS),$(OPTS),protocol)
endif

$(ENGINE_DIR)/shared-ram: $(VORTEX_HOME)/tests/rtlsim/shared_ram.cpp $(SRC_DIR)/vcs/runtime.h $(SIM_COMMON_DIR)/mem.cpp $(SIM_COMMON_DIR)/mem.h $(SW_COMMON_DIR)/util.cpp $(CONFIG_FILE)
	$(CXX) $(CXXFLAGS) -I$(SRC_DIR)/vcs $(VORTEX_HOME)/tests/rtlsim/shared_ram.cpp $(SIM_COMMON_DIR)/mem.cpp $(SW_COMMON_DIR)/util.cpp -pthread -o $@

.PHONY: check-shared-ram
check-shared-ram: $(ENGINE_DIR)/shared-ram
	$<

.PHONY: check-vcs-runtime
check-vcs-runtime:
ifeq ($(SIMULATOR),vcs)
	$(MAKE) -C $(ROOT_DIR)/sim/rtlsim SIMULATOR=vcs DESTDIR=$(ENGINE_DIR)/runtime $(ENGINE_DIR)/runtime/librtlsim.so
	$(CXX) $(CXXFLAGS) $(VORTEX_HOME)/tests/rtlsim/runtime.cpp -L$(ENGINE_DIR)/runtime -Wl,-rpath,$(ENGINE_DIR)/runtime -lrtlsim -o $(ENGINE_DIR)/runtime-check
	$(ENGINE_DIR)/runtime-check
else
	$(error check-vcs-runtime requires SIMULATOR=vcs)
endif

clean:
	rm -rf .protocol protocol
