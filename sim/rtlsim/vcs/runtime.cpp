#include "runtime.h"
#include <rtlsim.h>
#include "vc_hdrs.h"
#include <mem.h>
#include <iostream>
#include <unistd.h>

namespace {
int host_fd = -1;
}

void vortex::vcs::poll_host() {
  if (host_fd >= 0) check_peer(host_fd);
}

extern "C" void rtlsim_host(int fd, int page_size, int* status) {
  *status = 0;
  host_fd = fd;
  try {
    if (page_size < 4096 || (page_size & (page_size - 1))) {
      throw std::invalid_argument("Invalid VCS runtime page size");
    }
    vortex::RAM ram(0, page_size);
    ram.attach_shared({4, 5, uint32_t(page_size)});
    close(4);
    close(5);
    vortex::Processor processor;
    processor.attach_ram(&ram);
    vortex::vcs::Response response{};
    vortex::vcs::send(fd, &response, sizeof(response));
    vortex::vcs::Request request{};
    while (vortex::vcs::receive(fd, &request, sizeof(request))) {
      response = {};
      switch (request.command) {
      case vortex::vcs::Quit:
        host_fd = -1;
        close(fd);
        return;
      case vortex::vcs::Write:
        processor.dcr_write(request.address, request.data);
        break;
      case vortex::vcs::Read:
        processor.dcr_read(request.address, request.data, &response.value);
        break;
      case vortex::vcs::Run:
        processor.run();
        break;
      default:
        throw std::runtime_error("Invalid VCS runtime command");
      }
      vortex::vcs::send(fd, &response, sizeof(response));
    }
    throw std::runtime_error("VCS host disconnected without a shutdown command");
  } catch (const std::exception& error) {
    std::cerr << "rtlsim: " << error.what() << std::endl;
    *status = 1;
  }
  host_fd = -1;
  close(fd);
}
