#include <exception>
#include <iostream>
#include <unistd.h>
#include "program.h"

int main(int argc, char** argv) {
  try {
    int status = vortex::run_program(argc, argv);
    std::cout.flush();
    std::cerr.flush();
    _exit(status);
  } catch (const std::exception& error) {
    std::cerr << "rtlsim: " << error.what() << std::endl;
    return 1;
  }
}
