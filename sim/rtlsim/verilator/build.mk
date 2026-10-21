TOP = testbench

ifdef FSDB
    .PHONY: check-verilator-fsdb
    prepare: check-verilator-fsdb
    check-verilator-fsdb:
	@for name in rtlsim librtlsim.so; do \
	  if [ -f "$(DESTDIR)/$$name" ] || [ -L "$(DESTDIR)/$$name" ]; then rm -f "$(DESTDIR)/$$name"; fi; \
	done
	@echo 'FSDB requires SIMULATOR=vcs; Verilator supports VCD and SAIF' >&2
	@exit 1
endif

VL_FLAGS = --exe
VL_FLAGS += --language 1800-2012 --assert -Wall -Wpedantic
VL_FLAGS += -Wno-DECLFILENAME -Wno-REDEFMACRO
VL_FLAGS += --x-initial unique --x-assign unique
VL_FLAGS += $(CURDIR)/verilator/verilator.vlt
VL_FLAGS += $(RTL_DEFINES)
VL_FLAGS += $(RTL_INCLUDE)
VL_FLAGS += $(RTL_PKGS)
VL_FLAGS += $(RTL_PRE_SRCS)
VL_FLAGS += --cc $(TOP) --top-module $(TOP)

# Enable Verilator multithreaded simulation
THREADS ?= 4
VL_FLAGS += -j $(THREADS)
VL_FLAGS += -MAKEFLAGS CXX=$(CXX) -MAKEFLAGS LINK=$(CXX)
#VL_FLAGS += --threads $(THREADS)

# Debugging
ifdef DEBUG
	VL_FLAGS += $(DBG_FLAGS)
	CXXFLAGS += -g -O0 $(DBG_FLAGS)
else
	VL_FLAGS += -DNDEBUG
	CXXFLAGS += -DNDEBUG
	# The level goes through Verilator's per-class knobs, not CXXFLAGS: a level
	# in CXXFLAGS lands after them and so also optimizes the slow-path files
	# (constructors, reset, initialization), which run once and are most of the
	# compile time of a large model.
	VL_FLAGS += -MAKEFLAGS OPT_FAST=-O2 -MAKEFLAGS OPT_GLOBAL=-O2
endif

# Enable perf counters
ifdef PERF
	VL_FLAGS += -DPERF_ENABLE
	CXXFLAGS += -DPERF_ENABLE
endif

# Enable VCD waveform
ifdef VCD
	VL_FLAGS += --trace --trace-structs
	CXXFLAGS += -DVCD_OUTPUT
endif

# Enable SAIF tracing
ifdef SAIF
	VL_FLAGS += --trace-saif
	CXXFLAGS += -DSAIF_OUTPUT
endif

PROJECT := rtlsim
ENGINE_FLAGS = $(VL_FLAGS)
TOOL_VERSION = $(shell $(VERILATOR_PATH)/bin/verilator --version 2>&1)
ENGINE_SRCS = $(SRCS) $(SRC_DIR)/verilator/engine.cpp

# verilator --build runs its own make (parallelized by -j in VL_FLAGS) that
# cannot reach this make's jobserver, so it gets a clean MAKEFLAGS.
$(ENGINE_DIR)/$(PROJECT): $(ENGINE_SRCS) $(SRC_DIR)/common/program.cpp $(SRC_DIR)/verilator/main.cpp $(CONFIG_FILE) $(RTL_SRCS) $(COMMON_HEADERS) $(BUILD_INPUTS) verilator/verilator.vlt
	MAKEFLAGS= $(VERILATOR_PATH)/bin/verilator --build $(VL_FLAGS) $(ENGINE_SRCS) $(SRC_DIR)/common/program.cpp $(SRC_DIR)/verilator/main.cpp -CFLAGS '$(CXXFLAGS)' -LDFLAGS '$(LDFLAGS)' --MMD --Mdir $(ENGINE_DIR)/exe.obj -o $@

$(ENGINE_DIR)/lib$(PROJECT).so: $(ENGINE_SRCS) $(CONFIG_FILE) $(RTL_SRCS) $(COMMON_HEADERS) $(BUILD_INPUTS) verilator/verilator.vlt
	MAKEFLAGS= $(VERILATOR_PATH)/bin/verilator --build $(VL_FLAGS) $(ENGINE_SRCS) -CFLAGS '$(CXXFLAGS)' -LDFLAGS '-shared $(LDFLAGS)' --MMD --Mdir $(ENGINE_DIR)/lib.obj -o $@
