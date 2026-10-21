#include "engine.h"
#include "program.h"
#include "runtime.h"
#include "vc_hdrs.h"
#include <vpi_user.h>
#include <cstdint>
#include <exception>
#include <iostream>
#include <stdexcept>

#ifndef TRACE_START_TIME
#define TRACE_START_TIME 0ull
#endif
#ifndef TRACE_STOP_TIME
#define TRACE_STOP_TIME -1ull
#endif
static uint64_t trace_start_time = TRACE_START_TIME;
static uint64_t trace_stop_time = TRACE_STOP_TIME;
bool sim_trace_enabled() {
  s_vpi_time time{};
  time.type = vpiSimTime;
  vpi_get_time(nullptr, &time);
  uint64_t timestamp = ((uint64_t(time.high) << 32) | time.low) / 5000;
  return timestamp >= trace_start_time && timestamp < trace_stop_time;
}

extern "C" svBit rtlsim_trace_enabled() { return sim_trace_enabled(); }

namespace vortex {
class VcsEngine : public Engine {
public:
  void step() override {
    rtlsim_step();
    if (svIsDisabledState()) {
      svAckDisabledState();
      throw std::runtime_error("VCS clock task was disabled");
    }
    if ((++steps_ & 1023) == 0) vcs::poll_host();
  }
  void enable_assertions() override { rtlsim_assertions(); }
private:
  uint32_t steps_ = 0;
};
std::unique_ptr<Engine> make_engine() { return std::make_unique<VcsEngine>(); }
}

extern "C" void rtlsim_program(const char* program, int* status) {
  try {
    char name[] = "rtlsim";
    char* argv[] = {name, const_cast<char*>(program), nullptr};
    *status = vortex::run_program(2, argv);
  } catch (const std::exception& error) {
    std::cerr << "rtlsim: " << error.what() << std::endl;
    *status = 1;
  }
}
