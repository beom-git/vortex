#include <mem.h>
#include "runtime.h"
#include <cstdint>
#include <atomic>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <thread>
#include <vector>
#include <sys/wait.h>
#include <unistd.h>

static void check_logic_ram() {
  vortex::RAM ram(0, 4096);
  uint8_t data[] = {0xa6, 0x82, 0xff, 0x00, 0x53, 0x17};
  uint8_t state[] = {0x24, 0x24, 0xff, 0xff, 0x00, 0x80};
  uint8_t actual_data[sizeof(data)];
  uint8_t actual_state[sizeof(state)];
  ram.write_logic(data, state, 4094, sizeof(data));
  ram.copy(4095, 4094, sizeof(data));
  ram.copy(4094, 4095, sizeof(data));
  ram.read_logic(actual_data, actual_state, 4094, sizeof(data));
  for (unsigned i = 0; i < sizeof(data); ++i) {
    if (actual_data[i] != data[i] || actual_state[i] != state[i]) {
      throw std::runtime_error("RAM copy lost X/Z state");
    }
  }
  bool rejected = false;
  try { ram.read(actual_data, 4094, sizeof(data)); }
  catch (const std::runtime_error&) { rejected = true; }
  if (!rejected) {
    throw std::runtime_error("host read silently converted X/Z");
  }
  rejected = false;
  try { (void)ram[4094]; }
  catch (const std::runtime_error&) { rejected = true; }
  if (!rejected) {
    throw std::runtime_error("byte reference silently converted X/Z");
  }
  ram.write(data, 4094, 2);
  ram.read_logic(actual_data, actual_state, 4094, sizeof(data));
  for (unsigned i = 0; i < sizeof(data); ++i) {
    if (actual_state[i] != (i < 2 ? 0 : state[i])) {
      throw std::runtime_error("known write cleared unrelated X/Z state");
    }
  }
  ram.clear();
  ram.read_logic(actual_data, actual_state, 4094, sizeof(data));
  for (unsigned i = 0; i < sizeof(data); ++i) {
    if (actual_state[i] != 0) {
      throw std::runtime_error("RAM clear retained X/Z state");
    }
  }
}

int main() {
  try {
    check_logic_ram();
    int sockets[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sockets)) throw std::runtime_error("socketpair failed");
    vortex::vcs::check_peer(sockets[0]);
    close(sockets[1]);
    bool disconnected = false;
    try { vortex::vcs::check_peer(sockets[0]); } catch (const std::runtime_error&) { disconnected = true; }
    close(sockets[0]);
    if (!disconnected) throw std::runtime_error("VCS peer disconnect was not detected");
    vortex::RAM ram(0, 4096);
    auto memory = ram.share();
    const uint64_t address = (uint64_t(1) << VX_CFG_MEM_ADDR_WIDTH) - 4096;
    ram[address] = 0x12;
    uint8_t logic_data = 0xa6;
    uint8_t logic_state = 0x24;
    ram.write_logic(&logic_data, &logic_state, address + 128, 1);
    pid_t child = fork();
    if (child < 0) throw std::runtime_error("fork failed");
    if (child == 0) {
      try {
        vortex::RAM peer(0, 4096);
        peer.attach_shared(memory);
        const auto& view = peer;
        if (view[address] != 0x12 || view[8192] != 0x0d || peer.size() != 4096) _exit(1);
        uint8_t data = 0, state = 0;
        peer.read_logic(&data, &state, address + 128, 1);
        if (data != 0xa6 || state != 0x24) {
          _exit(4);
        }
        data = 0x82;
        peer.write_logic(&data, &state, address + 129, 1);
        peer[address + 1] = 0x34;
        peer[4096] = 0x56;
        if (view[4097] != 0xf0 || peer.size() != 8192) _exit(2);
      } catch (...) {
        _exit(3);
      }
      _exit(0);
    }
    int status = 0;
    if (waitpid(child, &status, 0) != child || !WIFEXITED(status) || WEXITSTATUS(status)) {
      throw std::runtime_error("shared RAM child failed");
    }
    const auto& view = ram;
    uint8_t data = 0, state = 0;
    ram.read_logic(&data, &state, address + 129, 1);
    if (data != 0x82 || state != 0x24) {
      throw std::runtime_error("shared X/Z state was lost");
    }
    bool unknown_rejected = false;
    try { ram.read(&data, address + 129, 1); }
    catch (const std::runtime_error&) { unknown_rejected = true; }
    if (!unknown_rejected) {
      throw std::runtime_error("shared host read silently converted X/Z");
    }
    data = 0x56;
    ram.write(&data, address + 129, 1);
    if (view[address + 1] != 0x34 || view[4096] != 0x56 || ram.size() != 8192) {
      throw std::runtime_error("shared RAM writes are not coherent");
    }
    bool rejected = false;
    try { ram.clear(); } catch (const std::logic_error&) { rejected = true; }
    if (!rejected) throw std::runtime_error("shared RAM clear must fail explicitly");
    std::vector<std::unique_ptr<vortex::RAM>> peers;
    for (int i = 0; i < 8; ++i) {
      peers.emplace_back(new vortex::RAM(0, 4096));
      peers.back()->attach_shared(memory);
      peers.back()->read_logic(&data, &state, address + 129, 1);
      if (data != 0x56 || state != 0) {
        throw std::runtime_error("shared known overwrite retained X/Z");
      }
    }
    std::atomic<int> ready{0};
    std::vector<std::thread> threads;
    for (int i = 0; i < 8; ++i) {
      threads.emplace_back([&, i] {
        ++ready;
        while (ready.load() != 8) std::this_thread::yield();
        for (uint64_t page = 0; page < 256; ++page) {
          (*peers[i])[0x10000 + page * 4096 + i] = uint8_t(0x80 + i);
        }
      });
    }
    for (auto& thread : threads) thread.join();
    for (uint64_t page = 0; page < 256; ++page) {
      for (int i = 0; i < 8; ++i) {
        if (view[0x10000 + page * 4096 + i] != uint8_t(0x80 + i)) {
          throw std::runtime_error("shared RAM initialization overwrote another thread's data");
        }
      }
    }
    if (ram.size() != 258 * 4096) throw std::runtime_error("shared RAM page initialized more than once");
    std::cout << "shared RAM PASS" << std::endl;
  } catch (const std::exception& error) {
    std::cerr << error.what() << std::endl;
    return 1;
  }
}
