#include "bridge.h"
#include <svdpi.h>

using vortex::Bridge;

extern "C" void rtlsim_poll(int* command, unsigned* address, unsigned* data) {
  auto& bridge = Bridge::active();
  *command = bridge.command;
  *address = bridge.address;
  *data = bridge.data;
  bridge.command = 0;
}

extern "C" void rtlsim_complete(unsigned result) {
  auto& bridge = Bridge::active();
  bridge.result = result;
  bridge.done = true;
}

extern "C" void rtlsim_request(int bank, svBit write, unsigned long long address,
                                 unsigned long long tag, const svBitVecVal* byteen,
                                 const svLogicVecVal* data) {
  std::array<uint32_t, (VX_CFG_PLATFORM_MEMORY_DATA_SIZE + 3) / 4> values{}, states{};
  for (unsigned i = 0; i < values.size(); ++i) {
    values[i] = data[i].aval;
    states[i] = data[i].bval;
  }
  Bridge::active().request(bank, write, address, tag, byteen, values.data(), states.data());
}

extern "C" svBit rtlsim_response(int bank, svLogicVecVal* data, unsigned long long* tag) {
  uint64_t value = 0;
  std::array<uint32_t, (VX_CFG_PLATFORM_MEMORY_DATA_SIZE + 3) / 4> values{}, states{};
  bool valid = Bridge::active().response(bank, values.data(), states.data(), &value);
  for (unsigned i = 0; i < values.size(); ++i) {
    data[i].aval = values[i];
    data[i].bval = states[i];
  }
  *tag = value;
  return valid;
}

extern "C" void rtlsim_memory_tick() { Bridge::active().tick(); }
extern "C" svBit rtlsim_stopped() { return Bridge::active().stop; }
