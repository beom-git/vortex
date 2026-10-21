#pragma once

#include <array>
#include <cstdint>
#include <deque>
#include <memory>
#include <VX_config.h>
#include <dram_sim.h>

namespace vortex {
class RAM;
class HostMonitor;
class CoutDrainer;

class Bridge {
public:
  enum Command { Reset = 1, Write = 2, Read = 3, Run = 4 };
  struct Request {
    std::array<uint8_t, VX_CFG_PLATFORM_MEMORY_DATA_SIZE> data{};
    std::array<uint8_t, VX_CFG_PLATFORM_MEMORY_DATA_SIZE> state{};
    uint64_t bank_addr;
    uint64_t tag;
    bool write;
    bool ready = false;
  };

  Bridge();
  ~Bridge();
  void submit(Command command, uint32_t address = 0, uint32_t data = 0);
  void request(int bank, bool write, uint64_t address, uint64_t tag,
               const uint32_t* byteen, const uint32_t* data, const uint32_t* state);
  bool response(int bank, uint32_t* data, uint32_t* state, uint64_t* tag);
  void tick();
  void activate();
  static Bridge& active();

  RAM* ram = nullptr;
  HostMonitor* monitor = nullptr;
  CoutDrainer* drainer = nullptr;
  int command = 0;
  uint32_t address = 0;
  uint32_t data = 0;
  uint32_t result = 0;
  bool done = true;
  bool stop = false;

private:
  // DRAM callbacks borrow requests until completion; presented responses belong to SV.
  DramSim dram_;
  std::array<std::deque<std::unique_ptr<Request>>, VX_CFG_PLATFORM_MEMORY_NUM_BANKS> pending_;
  std::array<std::deque<Request*>, VX_CFG_PLATFORM_MEMORY_NUM_BANKS> queued_;
};
}
