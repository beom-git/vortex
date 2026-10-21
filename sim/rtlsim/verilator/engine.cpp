#include "engine.h"
#include "Vtestbench.h"
#include <cstdlib>
#include <stdexcept>
#ifdef VCD_OUTPUT
#include <verilated_vcd_c.h>
#endif
#ifdef SAIF_OUTPUT
#include <verilated_saif_c.h>
#endif
#if defined(VCD_OUTPUT) && defined(SAIF_OUTPUT)
#error "VCD_OUTPUT and SAIF_OUTPUT cannot both be defined"
#endif
#ifndef VERILATOR_RESET_VALUE
#define VERILATOR_RESET_VALUE 2
#endif
#ifndef TRACE_START_TIME
#define TRACE_START_TIME 0ull
#endif
#ifndef TRACE_STOP_TIME
#define TRACE_STOP_TIME -1ull
#endif

static thread_local uint64_t timestamp = 0;
double sc_time_stamp() { return timestamp; }
static uint64_t trace_start_time = TRACE_START_TIME;
static uint64_t trace_stop_time = TRACE_STOP_TIME;
bool sim_trace_enabled() {
  return timestamp >= trace_start_time && timestamp < trace_stop_time;
}

namespace vortex {
class VerilatorEngine : public Engine {
public:
  VerilatorEngine() {
    timestamp = 0;

    context_ = new VerilatedContext();

    context_->randReset(VERILATOR_RESET_VALUE);
    context_->randSeed(50);

    context_->assertOn(false);

    device_ = new Vtestbench(context_);

  #ifdef VCD_OUTPUT
    context_->traceEverOn(true);
    tfp_ = new VerilatedVcdC();
    device_->trace(tfp_, 99);
    const char* vcd_file = std::getenv("VCD_FILE");
    tfp_->open(vcd_file ? vcd_file : "trace.vcd");
  #endif

  #ifdef SAIF_OUTPUT
    context_->traceEverOn(true);
    sfp_ = new VerilatedSaifC();
    device_->trace(sfp_, 99);
    const char* saif_file = std::getenv("SAIF_FILE");
    sfp_->open(saif_file ? saif_file : "trace.saif");
  #endif

  }

  ~VerilatorEngine() override {
    finish();

    delete device_;
    delete context_;
  }

  void finish() override {
  #ifdef VCD_OUTPUT
    if (tfp_) {
      tfp_->close();
      delete tfp_;
      tfp_ = nullptr;
    }
  #endif
  #ifdef SAIF_OUTPUT
    if (sfp_) {
      sfp_->close();
      delete sfp_;
      sfp_ = nullptr;
    }
  #endif
  }

  void enable_assertions() override { context_->assertOn(true); }

  void step() override {
    device_->clk = 0;
    eval();
    device_->clk = 1;
    eval();
    if (context_->gotFinish()) {
      throw std::runtime_error("RTL simulation terminated before command completion");
    }
  }

private:
  void eval() {
    context_->time(timestamp);
    device_->eval();
#ifdef VCD_OUTPUT
    if (sim_trace_enabled()) {
      tfp_->dump(timestamp);
    }
#endif
#ifdef SAIF_OUTPUT
    if (sim_trace_enabled()) {
      sfp_->dump(timestamp);
    }
#endif
    ++timestamp;
  }
  VerilatedContext* context_;
  Vtestbench* device_;
#ifdef VCD_OUTPUT
  VerilatedVcdC* tfp_;
#endif
#ifdef SAIF_OUTPUT
  VerilatedSaifC* sfp_;
#endif
};

std::unique_ptr<Engine> make_engine() { return std::make_unique<VerilatorEngine>(); }
}
