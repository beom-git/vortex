#pragma once

#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <system_error>
#include <sys/socket.h>
#include <poll.h>

namespace vortex {
namespace vcs {

enum Command : uint32_t { Quit, Write, Read, Run };
struct Request { uint32_t command, address, data; };
struct Response { uint32_t value; };
void poll_host();

inline void check_peer(int fd) {
  struct pollfd connection{fd, 0, 0};
  int result;
  do { result = poll(&connection, 1, 0); } while (result < 0 && errno == EINTR);
  if (result < 0) throw std::system_error(errno, std::generic_category(), "VCS runtime poll");
  if (connection.revents & (POLLHUP | POLLERR | POLLNVAL)) {
    throw std::runtime_error("VCS host disconnected during execution");
  }
}

inline void send(int fd, const void* data, std::size_t size) {
  const char* bytes = static_cast<const char*>(data);
  while (size) {
    ssize_t count = ::send(fd, bytes, size, MSG_NOSIGNAL);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) throw std::system_error(errno, std::generic_category(), "VCS runtime send");
    bytes += count;
    size -= count;
  }
}

inline bool receive(int fd, void* data, std::size_t size) {
  char* bytes = static_cast<char*>(data);
  bool started = false;
  while (size) {
    ssize_t count = recv(fd, bytes, size, 0);
    if (count < 0 && errno == EINTR) continue;
    if (count < 0) throw std::system_error(errno, std::generic_category(), "VCS runtime receive");
    if (count == 0) {
      if (started) throw std::runtime_error("VCS runtime returned an incomplete response");
      return false;
    }
    started = true;
    bytes += count;
    size -= count;
  }
  return true;
}

}
}
