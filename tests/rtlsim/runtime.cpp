#include <rtlsim.h>
#include <mem.h>
#include <VX_types.h>
#include <fstream>
#include <fcntl.h>
#include <iostream>
#include <stdexcept>
#include <string>
#include <signal.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <unistd.h>

static pid_t worker_pid() {
  std::ifstream children("/proc/self/task/" + std::to_string(getpid()) + "/children");
  pid_t worker = -1;
  if (!(children >> worker) || worker <= 0) throw std::runtime_error("Cannot find the VCS test worker");
  return worker;
}

int main() {
  try {
    for (bool crash : {false, true}) {
      vortex::RAM ram(0, 4096);
      vortex::Processor processor;
      processor.attach_ram(&ram);
      pid_t worker = worker_pid();
      processor.dcr_write(VX_DCR_KMU_STARTUP_ADDR0, 0x80000000);
      if (crash) {
        if (kill(worker, SIGKILL)) {
          throw std::runtime_error("Cannot terminate the VCS test worker");
        }
      }
      bool failed = false;
      try { processor.finish(); }
      catch (const std::exception&) { failed = true; }
      if (failed != crash) throw std::runtime_error("VCS shutdown returned the wrong status");
      processor.finish();
      if (crash && (waitpid(worker, nullptr, WNOHANG) != -1 || errno != ECHILD)) {
        throw std::runtime_error("VCS worker was not reaped");
      }
    }
    // Adopt the orphan worker so its native exit status can be checked.
    if (prctl(PR_SET_CHILD_SUBREAPER, 1)) throw std::runtime_error("Cannot adopt VCS test workers");
    int connection[2];
    if (pipe2(connection, O_CLOEXEC)) throw std::runtime_error("Cannot create VCS test pipe");
    pid_t host = fork();
    if (host < 0) throw std::runtime_error("Cannot fork VCS test host");
    if (host == 0) {
      close(connection[0]);
      vortex::RAM ram(0, 4096);
      vortex::Processor processor;
      processor.attach_ram(&ram);
      processor.dcr_write(VX_DCR_KMU_STARTUP_ADDR0, 0x80000000);
      pid_t worker = worker_pid();
      if (write(connection[1], &worker, sizeof(worker)) != sizeof(worker)) _exit(1);
      for (;;) pause();
    }
    close(connection[1]);
    pid_t worker = -1;
    ssize_t received = read(connection[0], &worker, sizeof(worker));
    close(connection[0]);
    kill(host, SIGKILL);
    waitpid(host, nullptr, 0);
    if (received != sizeof(worker) || worker <= 0) throw std::runtime_error("VCS idle disconnect setup failed");
    int status = 0;
    if (waitpid(worker, &status, 0) != worker || !WIFEXITED(status) || WEXITSTATUS(status) != 3) {
      throw std::runtime_error("VCS idle disconnect did not fail with native status 3");
    }
    std::cout << "VCS runtime shutdown PASS" << std::endl;
  } catch (const std::exception& error) {
    std::cerr << error.what() << std::endl;
    return 1;
  }
}
