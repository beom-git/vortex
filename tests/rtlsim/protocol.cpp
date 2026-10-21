#include <VX_types.h>
#include <util.h>
#include <mem.h>
#include <iostream>
#include <cstring>
#include <stdexcept>
#include <string>
#include <rtlsim.h>
#include "program.h"

static uint64_t bank_address(unsigned bank) {
#if VX_CFG_PLATFORM_MEMORY_INTERLEAVE == 1
  return (uint64_t(7) * VX_CFG_PLATFORM_MEMORY_NUM_BANKS + bank) * VX_CFG_PLATFORM_MEMORY_DATA_SIZE;
#else
  unsigned bank_bits = VX_CFG_PLATFORM_MEMORY_ADDR_WIDTH - vortex::log2ceil(VX_CFG_PLATFORM_MEMORY_NUM_BANKS);
  return (uint64_t(7) + (uint64_t(bank) << bank_bits)) * VX_CFG_PLATFORM_MEMORY_DATA_SIZE;
#endif
}

int vortex::run_program(int argc, char** argv) {
  try {
    uint32_t dcr_value = 0xa5a55a5a;
    const char* faults[] = {"control", "address", "tag", "byteen", "write", "disabled"};
    for (unsigned i = 0; i < sizeof(faults) / sizeof(faults[0]); ++i) {
      for (unsigned state = 1; state <= 2; ++state) {
        std::string option = std::string(state == 1 ? "--x-" : "--z-") + faults[i];
        if (argc == 2 && option == argv[1]) {
          dcr_value = 0xa5a55a00 | (state << 4) | (i + 1);
        }
      }
    }
    vortex::RAM ram(0, 4096);
    vortex::Processor processor;
    processor.attach_ram(&ram);
    for (unsigned bank = 0; bank < VX_CFG_PLATFORM_MEMORY_NUM_BANKS; ++bank) {
      for (unsigned i = 0; i < VX_CFG_PLATFORM_MEMORY_DATA_SIZE; ++i) {
        ram[bank_address(bank) + i] = 0x55;
      }
    }
    processor.dcr_write((argc == 2 && std::strcmp(argv[1], "--assert") == 0) ? 0x124 : 0x123, dcr_value);
    uint32_t result = 0;
    processor.dcr_read(0x123, 0, &result);
    if (result != dcr_value) {
      throw std::runtime_error("DCR response mismatch");
    }
    processor.run();
    for (unsigned bank = 0; bank < VX_CFG_PLATFORM_MEMORY_NUM_BANKS; ++bank) {
      for (unsigned i = 0; i < VX_CFG_PLATFORM_MEMORY_DATA_SIZE; ++i) {
        uint8_t expected = (i % 2 == 0) ? uint8_t(i + bank) : 0x55;
        if (ram[bank_address(bank) + i] != expected) {
          throw std::runtime_error("bank address or byte enable mismatch");
        }
      }
    }
    std::cout << "rtlsim protocol PASS" << std::endl;
  } catch (const std::exception& error) {
    std::cerr << error.what() << std::endl;
    return 1;
  }
  return 0;
}
