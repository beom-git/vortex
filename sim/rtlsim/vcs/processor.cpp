#include <rtlsim.h>
#include "runtime.h"
#include <mem.h>
#include <cstdlib>
#include <dlfcn.h>
#include <filesystem>
#include <fcntl.h>
#include <iostream>
#include <mutex>
#include <spawn.h>
#include <string>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>

extern char** environ;

namespace {
void runtime_anchor() {}
}

using namespace vortex;

class Processor::Impl {
public:
  ~Impl() {
    try { finish(); }
    catch (const std::exception& error) { std::cerr << "rtlsim: " << error.what() << std::endl; }
  }

  void finish() {
    std::lock_guard<std::mutex> guard(mutex_);
    std::exception_ptr failure;
    if (fd_ >= 0) {
      vcs::Request request{vcs::Quit, 0, 0};
      try { vcs::send(fd_, &request, sizeof(request)); }
      catch (...) { failure = std::current_exception(); }
      close(fd_);
      fd_ = -1;
    }
    if (pid_ > 0) {
      int status = 0;
      pid_t result;
      do { result = waitpid(pid_, &status, 0); } while (result < 0 && errno == EINTR);
      if (result < 0) {
        failure = std::make_exception_ptr(std::system_error(errno, std::generic_category(), "wait for VCS runtime"));
      } else if (!WIFEXITED(status) || WEXITSTATUS(status)) {
        failure = std::make_exception_ptr(std::runtime_error("VCS runtime terminated abnormally (wait status " + std::to_string(status) + ")"));
      }
      pid_ = -1;
    }
    failed_ = true;
    if (failure) std::rethrow_exception(failure);
  }

  void attach(RAM* ram) {
    std::lock_guard<std::mutex> guard(mutex_);
    if (!ram || memory_.data_fd >= 0 || failed_) throw std::invalid_argument("Attach VCS RAM once before issuing commands");
    memory_ = ram->share();
    // Acquire the native runtime before an asynchronous command's timeout starts.
    try { start(); }
    catch (...) {
      failed_ = true;
      throw;
    }
  }

  uint32_t execute(vcs::Command command, uint32_t address = 0, uint32_t data = 0) {
    std::lock_guard<std::mutex> guard(mutex_);
    if (failed_) throw std::runtime_error("VCS runtime has terminated");
    if (fd_ < 0) throw std::runtime_error("Attach RAM before issuing VCS commands");
    try {
      vcs::Request request{command, address, data};
      vcs::send(fd_, &request, sizeof(request));
      vcs::Response response{};
      if (!vcs::receive(fd_, &response, sizeof(response))) {
        throw std::runtime_error("VCS runtime exited before completing the command");
      }
      return response.value;
    } catch (...) {
      failed_ = true;
      throw;
    }
  }

private:
  void start() {
    if (memory_.data_fd < 0) throw std::runtime_error("Attach RAM before starting VCS");
    Dl_info info{};
    if (!dladdr(reinterpret_cast<void*>(&runtime_anchor), &info)) {
      throw std::runtime_error("Cannot locate the VCS runtime library");
    }
    auto executable = std::filesystem::canonical(info.dli_fname).parent_path() / "simv";
    std::vector<std::string> arguments = {executable.string(), "-exitstatus", "-assert", "finish_maxfail=1", "+vcs+lic+wait", "+runtime_fd=3",
      "+runtime_page_size=" + std::to_string(memory_.page_size),
      std::string("+vcd=") + (std::getenv("VCD_FILE") ? std::getenv("VCD_FILE") : "trace.vcd"),
      std::string("+fsdb=") + (std::getenv("FSDB_FILE") ? std::getenv("FSDB_FILE") : "trace.fsdb")};
    std::vector<char*> argv;
    for (auto& argument : arguments) argv.push_back(argument.data());
    argv.push_back(nullptr);
    int sockets[2];
    if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sockets)) {
      throw std::system_error(errno, std::generic_category(), "VCS socketpair");
    }
    int source[3] = {-1, -1, -1};
    posix_spawn_file_actions_t actions;
    int error = posix_spawn_file_actions_init(&actions);
    if (error) {
      close(sockets[0]);
      close(sockets[1]);
      throw std::system_error(error, std::generic_category(), "VCS spawn actions");
    }
    int descriptors[] = {sockets[1], memory_.data_fd, memory_.state_fd};
    for (int i = 0; i < 3 && !error; ++i) {
      source[i] = fcntl(descriptors[i], F_DUPFD_CLOEXEC, 6);
      error = source[i] < 0 ? errno : posix_spawn_file_actions_adddup2(&actions, source[i], 3 + i);
    }
    if (!error) error = posix_spawn(&pid_, executable.c_str(), &actions, nullptr, argv.data(), environ);
    posix_spawn_file_actions_destroy(&actions);
    for (int descriptor : source) if (descriptor >= 0) close(descriptor);
    close(sockets[1]);
    if (error) {
      close(sockets[0]);
      pid_ = -1;
      throw std::system_error(error, std::generic_category(), "VCS spawn");
    }
    fd_ = sockets[0];
    vcs::Response response{};
    if (!vcs::receive(fd_, &response, sizeof(response))) {
      throw std::runtime_error("VCS runtime failed to initialize; check its diagnostic and runtime license");
    }
  }

  RAM::SharedMemory memory_{-1, -1, 0};
  std::mutex mutex_;
  int fd_ = -1;
  pid_t pid_ = -1;
  bool failed_ = false;
};

Processor::Processor() : impl_(new Impl()) {}
Processor::~Processor() { delete impl_; }
void Processor::attach_ram(RAM* ram) { impl_->attach(ram); }
void Processor::finish() { impl_->finish(); }
void Processor::run(HostMonitor* monitor, CoutDrainer* drainer) {
  if (monitor || drainer) throw std::invalid_argument("VCS host runtime does not accept standalone monitors");
  impl_->execute(vcs::Run);
}
int Processor::dcr_write(uint32_t address, uint32_t value) {
  impl_->execute(vcs::Write, address, value);
  return 0;
}
int Processor::dcr_read(uint32_t address, uint32_t tag, uint32_t* value) {
  *value = impl_->execute(vcs::Read, address, tag);
  return 0;
}
