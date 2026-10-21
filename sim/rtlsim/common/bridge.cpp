#include "bridge.h"
#include <mem.h>
#include <host_monitor.h>
#include <cout_drainer.h>
#include <util.h>
#include <cstring>
#include <stdexcept>

using namespace vortex;
static thread_local Bridge* current_bridge = nullptr;

Bridge::Bridge() : dram_(DramSim::platform_config()) {}

Bridge::~Bridge() {
  // Cancel callbacks before releasing the requests they borrow.
  dram_.reset();
  if (current_bridge == this) {
    current_bridge = nullptr;
  }
}

void Bridge::activate() { current_bridge = this; }
Bridge& Bridge::active() {
  if (!current_bridge) {
    throw std::runtime_error("rtlsim DPI called without an active processor");
  }
  return *current_bridge;
}

void Bridge::submit(Command op, uint32_t addr, uint32_t value) {
  command = op;
  address = addr;
  data = value;
  done = false;
  stop = false;
}

void Bridge::request(int bank, bool write, uint64_t address, uint64_t tag,
                     const uint32_t* byteen, const uint32_t* data, const uint32_t* state) {
  if (!ram) {
    throw std::runtime_error("rtlsim memory request without attached RAM");
  }
#if VX_CFG_PLATFORM_MEMORY_INTERLEAVE == 1
  uint64_t byte_addr = (address * VX_CFG_PLATFORM_MEMORY_NUM_BANKS + bank) * VX_CFG_PLATFORM_MEMORY_DATA_SIZE;
#else
  constexpr unsigned bank_bits = VX_CFG_PLATFORM_MEMORY_ADDR_WIDTH - log2ceil(VX_CFG_PLATFORM_MEMORY_NUM_BANKS);
  uint64_t byte_addr = (address + (uint64_t(bank) << bank_bits)) * VX_CFG_PLATFORM_MEMORY_DATA_SIZE;
#endif
  auto req = std::make_unique<Request>();
  req->tag = tag;
  req->bank_addr = address * VX_CFG_PLATFORM_MEMORY_DATA_SIZE;
  req->write = write;
  if (write) {
    for (unsigned i = 0; i < VX_CFG_PLATFORM_MEMORY_DATA_SIZE; ++i) {
      if ((byteen[i / 32] >> (i % 32)) & 1) {
        uint8_t value = uint8_t(data[i / 4] >> (8 * (i % 4)));
        uint8_t value_state = uint8_t(state[i / 4] >> (8 * (i % 4)));
        ram->write_logic(&value, &value_state, byte_addr + i, 1);
      }
    }
  } else {
    ram->read_logic(req->data.data(), req->state.data(), byte_addr, req->data.size());
  }
  queued_.at(bank).push_back(req.get());
  pending_.at(bank).push_back(std::move(req));
}

bool Bridge::response(int bank, uint32_t* data, uint32_t* state, uint64_t* tag) {
  auto& queue = pending_.at(bank);
  if (queue.empty() || !queue.front()->ready) {
    return false;
  }
  auto& req = *queue.front();
  bool valid = !req.write;
  if (valid) {
    std::memset(data, 0, ((VX_CFG_PLATFORM_MEMORY_DATA_SIZE * 8 + 31) / 32) * sizeof(uint32_t));
    std::memset(state, 0, ((VX_CFG_PLATFORM_MEMORY_DATA_SIZE * 8 + 31) / 32) * sizeof(uint32_t));
    for (unsigned i = 0; i < req.data.size(); ++i) {
      data[i / 4] |= uint32_t(req.data[i]) << (8 * (i % 4));
      state[i / 4] |= uint32_t(req.state[i]) << (8 * (i % 4));
    }
    *tag = req.tag;
  }
  queue.pop_front();
  return valid;
}

void Bridge::tick() {
  dram_.tick();
  for (unsigned bank = 0; bank < queued_.size(); ++bank) {
    auto& queue = queued_[bank];
    if (!queue.empty() && dram_.can_accept(bank)) {
      auto req = queue.front();
      dram_.send_request(bank, req->bank_addr, req->write, [](void* arg) {
        static_cast<Request*>(arg)->ready = true;
        return true;
      }, req);
      queue.pop_front();
    }
  }
  if (drainer) {
    drainer->tick();
  }
  if (monitor && monitor->enabled()) {
    stop = monitor->tick(*ram);
  }
}
