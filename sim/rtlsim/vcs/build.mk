VCS_OPTS ?=
CXXFLAGS += -I$(ENGINE_DIR)

# TOP = testbench
TOP = vcs_top

# VL_FLAGS = --exe
# VCS builds a native executable by default.
VCS_FLAGS = -full64

# VL_FLAGS += --language 1800-2012
VCS_FLAGS += -sverilog

# VL_FLAGS += --assert
# Hierarchy support lets the runtime stop on the first assertion failure.
VCS_FLAGS += -assert enable_hier

# VL_FLAGS += -Wall -Wpedantic
VCS_FLAGS += +lint=all

# VL_FLAGS += -Wno-DECLFILENAME -Wno-REDEFMACRO
# VCS does not implement these Verilator lint categories.

# VL_FLAGS += --x-initial unique --x-assign unique
# VCS preserves four-state data; the common testbench rejects unknown controls.

# VL_FLAGS += $(CURDIR)/verilator/verilator.vlt
# Verilator lint configuration is not an input to VCS.

# VL_FLAGS += $(RTL_DEFINES)
VCS_FLAGS += $(patsubst -D%,+define+%,$(RTL_DEFINES))

# VL_FLAGS += $(RTL_INCLUDE)
VCS_FLAGS += $(patsubst -I%,+incdir+%,$(RTL_INCLUDE))

# VL_FLAGS += $(RTL_PKGS)
VCS_FLAGS += $(RTL_PKGS)

# VL_FLAGS += $(RTL_PRE_SRCS)
VCS_FLAGS += $(RTL_PRE_SRCS)

# VL_FLAGS += --cc $(TOP) --top-module $(TOP)
# VCS uses its own clock/entry wrapper around the same common testbench.
VCS_FLAGS += $(SRC_DIR)/common/testbench.sv $(SRC_DIR)/vcs/top.sv -top $(TOP)

# Verilator resolves module files through -I directories.
# VCS needs library directories in addition to preprocessor include directories.
VCS_FLAGS += $(foreach dir,$(RTL_DIRS),-y $(dir)) +libext+.sv+.v

# Verilator's engine advances time explicitly; VCS needs a default timescale.
VCS_FLAGS += -timescale=1ns/1ps

# THREADS ?= 4
THREADS ?= 4

# VL_FLAGS += -j $(THREADS)
VCS_FLAGS += -j$(THREADS)

# VL_FLAGS += -MAKEFLAGS CXX=$(CXX) -MAKEFLAGS LINK=$(CXX)
VCS_FLAGS += -cpp $(CXX) -cc $(CC)

# VL_FLAGS += --threads $(THREADS)
# Both engines keep single-threaded simulation; THREADS controls compilation only.

# Debugging
ifdef DEBUG
    # VL_FLAGS += $(DBG_FLAGS)
    VCS_FLAGS += $(patsubst -D%,+define+%,$(DBG_FLAGS))
    # CXXFLAGS += -g -O0 $(DBG_FLAGS)
    CXXFLAGS += -g -O0 $(DBG_FLAGS)
    VCS_FLAGS += -debug_access+all
else
    # VL_FLAGS += -DNDEBUG
    VCS_FLAGS += +define+NDEBUG
    # CXXFLAGS += -DNDEBUG
    CXXFLAGS += -DNDEBUG
    # VL_FLAGS += -MAKEFLAGS OPT_FAST=-O2 -MAKEFLAGS OPT_GLOBAL=-O2
    VCS_FLAGS += -CFLAGS -O2
endif

# Enable perf counters
ifdef PERF
    # VL_FLAGS += -DPERF_ENABLE
    VCS_FLAGS += +define+PERF_ENABLE
    # CXXFLAGS += -DPERF_ENABLE
    CXXFLAGS += -DPERF_ENABLE
endif

# Enable VCD waveform
ifdef VCD
    # VL_FLAGS += --trace --trace-structs
    VCS_FLAGS += -debug_access+all +define+VCD_OUTPUT
    # CXXFLAGS += -DVCD_OUTPUT
    CXXFLAGS += -DVCD_OUTPUT
endif

# Enable FSDB waveform
ifdef FSDB
    # Verilator has no FSDB writer; VCS loads the selected Verdi dumper.
    VCS_FLAGS += -debug_access+all +define+FSDB_OUTPUT
    FSDB_PLI_DIR := $(VERDI_HOME)/share/PLI/VCS/LINUX64
    FSDB_PLI_FILES := $(wildcard $(FSDB_PLI_DIR)/novas.tab $(FSDB_PLI_DIR)/verdi.tab $(FSDB_PLI_DIR)/pli.a $(FSDB_PLI_DIR)/libnovas.so $(FSDB_PLI_DIR)/fsdbClient $(FSDB_PLI_DIR)/libsscore_vcs*.so)
    BUILD_INPUTS += $(FSDB_PLI_FILES)
    .PHONY: check-vcs-fsdb
    prepare: check-vcs-fsdb
    check-vcs-fsdb:
	@if [ -z "$(VERDI_HOME)" ] || [ ! -r "$(FSDB_PLI_DIR)/novas.tab" ] || [ ! -r "$(FSDB_PLI_DIR)/pli.a" ]; then \
	  for name in rtlsim librtlsim.so; do \
	    if [ -f "$(DESTDIR)/$$name" ] || [ -L "$(DESTDIR)/$$name" ]; then rm -f "$(DESTDIR)/$$name"; fi; \
	  done; \
	  echo 'VCS FSDB requires VERDI_HOME with readable share/PLI/VCS/LINUX64/novas.tab and pli.a; load the Verdi environment' >&2; \
	  exit 1; \
	fi
endif

ifneq (,$(strip $(VCD)$(FSDB)))
    VCS_FLAGS += +define+WAVEFORM_OUTPUT
endif

# Enable SAIF tracing
ifdef SAIF
    # VL_FLAGS += --trace-saif
    # CXXFLAGS += -DSAIF_OUTPUT
    # Reject after removing published aliases so an old engine cannot be reused.
    .PHONY: check-vcs-saif
    prepare: check-vcs-saif
    check-vcs-saif:
	@for name in rtlsim librtlsim.so; do \
	  if [ -f "$(DESTDIR)/$$name" ] || [ -L "$(DESTDIR)/$$name" ]; then rm -f "$(DESTDIR)/$$name"; fi; \
	done
	@echo 'VCS native SAIF is blocked: hierarchy traversal fails with VPI-ITPTVOT on W-2024.09-SP1; use VCD=1 or FSDB=1 for waveform capture' >&2
	@exit 1
endif

# ENGINE_FLAGS = $(VL_FLAGS)
ENGINE_FLAGS = $(VCS_FLAGS) $(VCS_OPTS)

# TOOL_VERSION = $(shell $(VERILATOR_PATH)/bin/verilator --version 2>&1)
TOOL_VERSION = $(shell $(SIMULATOR) -ID 2>&1)
ifdef FSDB
    TOOL_VERSION += $(VERDI_HOME) $(shell stat -Lc '%n:%s:%y' $(FSDB_PLI_FILES) 2>/dev/null)
endif

# ENGINE_SRCS = $(SRCS) $(SRC_DIR)/verilator/engine.cpp
ENGINE_SRCS = $(SRCS) $(SRC_DIR)/common/program.cpp $(SRC_DIR)/vcs/engine.cpp $(SRC_DIR)/vcs/runtime.cpp

# Verilator's generated link command places archives after objects.
# VCS places -LDFLAGS before objects; -syslib places archives after their users.
# VCS emits C++ dependency files without including them in its generated makefile.
VCS_LDFLAGS = $(filter-out %.a,$(LDFLAGS))
VCS_SYSLIBS = $(filter %.a,$(LDFLAGS))

# $(ENGINE_DIR)/rtlsim: $(ENGINE_SRCS) $(SRC_DIR)/common/program.cpp $(SRC_DIR)/verilator/main.cpp $(CONFIG_FILE) $(RTL_SRCS) $(COMMON_HEADERS) $(BUILD_INPUTS) verilator/verilator.vlt
$(ENGINE_DIR)/rtlsim: $(ENGINE_SRCS) $(SRC_DIR)/vcs/runtime.h $(CONFIG_FILE) $(RTL_SRCS) $(COMMON_HEADERS) $(BUILD_INPUTS) vcs/run.sh $(SRC_DIR)/vcs/top.sv
	@command -v $(SIMULATOR) >/dev/null || { echo 'VCS executable not found; load the VCS environment or add vcs to PATH' >&2; exit 1; }
# MAKEFLAGS= $(VERILATOR_PATH)/bin/verilator --build $(VL_FLAGS) $(ENGINE_SRCS) $(SRC_DIR)/common/program.cpp $(SRC_DIR)/verilator/main.cpp -CFLAGS '$(CXXFLAGS)' -LDFLAGS '$(LDFLAGS)' --MMD --Mdir $(ENGINE_DIR)/exe.obj -o $@
	cd $(ENGINE_DIR) && MAKEFILES='$(wildcard $(ENGINE_DIR)/exe.obj/*.d)' $(SIMULATOR) $(ENGINE_FLAGS) $(ENGINE_SRCS) -CFLAGS '$(CXXFLAGS)' -LDFLAGS '$(VCS_LDFLAGS)' -syslib '$(VCS_SYSLIBS)' -o simv -Mdir=exe.obj
	cp vcs/run.sh $@
	chmod +x $@

# $(ENGINE_DIR)/librtlsim.so: $(ENGINE_SRCS) $(CONFIG_FILE) $(RTL_SRCS) $(COMMON_HEADERS) $(BUILD_INPUTS) verilator/verilator.vlt
# MAKEFLAGS= $(VERILATOR_PATH)/bin/verilator --build $(VL_FLAGS) $(ENGINE_SRCS) -CFLAGS '$(CXXFLAGS)' -LDFLAGS '-shared $(LDFLAGS)' --MMD --Mdir $(ENGINE_DIR)/lib.obj -o $@
# The host library transports commands and shares RAM; the native engine remains in simv.
HOST_SRCS = $(SRC_DIR)/vcs/processor.cpp $(SIM_COMMON_DIR)/mem.cpp $(SW_COMMON_DIR)/util.cpp
$(ENGINE_DIR)/librtlsim.so: $(ENGINE_DIR)/rtlsim $(HOST_SRCS) $(SRC_DIR)/vcs/runtime.h $(COMMON_HEADERS) $(CONFIG_FILE)
	$(CXX) $(CXXFLAGS) $(if $(DEBUG),,-O2) $(HOST_SRCS) -shared -pthread -ldl -o $@
