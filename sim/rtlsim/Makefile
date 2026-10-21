include ../common.mk

.DEFAULT_GOAL := all
SIMULATOR ?= verilator
ifneq ($(SIMULATOR),verilator)
ifneq ($(SIMULATOR),vcs)
$(error Unsupported SIMULATOR '$(SIMULATOR)'; choose verilator or vcs)
endif
endif

DESTDIR ?= $(CURDIR)
SRC_DIR := $(VORTEX_HOME)/sim/rtlsim
include common/sources.mk
ENGINE_DIR := $(abspath $(DESTDIR))/.rtlsim/$(SIMULATOR)
CONFIG_FILE := $(ENGINE_DIR)/config.stamp
BUILD_INPUTS := $(wildcard $(SRC_DIR)/*/*.mk) $(SRC_DIR)/Makefile $(ROOT_DIR)/config.mk $(wildcard $(ROOT_DIR)/sw/VX_*.h) $(wildcard $(ROOT_DIR)/hw/VX_*.vh)
COMMON_HEADERS := $(wildcard $(SRC_DIR)/common/*.h $(SIM_COMMON_DIR)/*.h $(SW_COMMON_DIR)/*.h $(DPI_DIR)/*.vh)
include $(SIMULATOR)/build.mk

.PHONY: all force prepare clean clean-lib clean-exe
all: $(DESTDIR)/rtlsim

prepare:
	@mkdir -p $(ENGINE_DIR)
	@for name in rtlsim librtlsim.so; do \
	  if [ -f "$(DESTDIR)/$$name" ] || [ -L "$(DESTDIR)/$$name" ]; then \
	    if [ "$$(readlink "$(DESTDIR)/$$name")" != "$(ENGINE_DIR)/$$name" ]; then rm -f "$(DESTDIR)/$$name"; fi; \
	  fi; \
	done

$(CONFIG_FILE): force | prepare
	@printf '%s\n' "$(SIMULATOR)" "$(TOOL_VERSION)" "$(ENGINE_FLAGS)" "$(CXX) $(shell $(CXX) --version 2>&1 | head -1) $(CXXFLAGS)" "$(CC) $(shell $(CC) --version 2>&1 | head -1)" "$(LDFLAGS)" "$(ENGINE_SRCS) $(COMMON_HEADERS) $(RTL_SRCS)" > $@.tmp
	@if ! cmp -s $@.tmp $@; then \
	  mv $@.tmp $@; \
	  rm -rf $(ENGINE_DIR)/exe.obj $(ENGINE_DIR)/lib.obj; \
	  rm -f $(ENGINE_DIR)/rtlsim $(ENGINE_DIR)/librtlsim.so $(ENGINE_DIR)/simv; \
	  for name in rtlsim librtlsim.so; do \
	    if [ -f "$(DESTDIR)/$$name" ] || [ -L "$(DESTDIR)/$$name" ]; then rm -f "$(DESTDIR)/$$name"; fi; \
	  done; \
	else rm -f $@.tmp; fi

$(DESTDIR)/rtlsim: $(ENGINE_DIR)/rtlsim force
	ln -sfn $(ENGINE_DIR)/rtlsim $@

$(DESTDIR)/librtlsim.so: $(ENGINE_DIR)/librtlsim.so force
	ln -sfn $(ENGINE_DIR)/librtlsim.so $@

clean-lib:
	rm -f $(DESTDIR)/librtlsim.so
	rm -rf $(ENGINE_DIR)/lib.obj $(ENGINE_DIR)/librtlsim.so

clean-exe:
	rm -f $(DESTDIR)/rtlsim
	rm -rf $(ENGINE_DIR)/exe.obj $(ENGINE_DIR)/rtlsim $(ENGINE_DIR)/simv $(ENGINE_DIR)/simv.daidir $(ENGINE_DIR)/csrc

clean: clean-lib clean-exe
