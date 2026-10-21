#pragma once

#include <memory>

namespace vortex {
class Engine {
public:
  virtual ~Engine() = default;
  virtual void step() = 0;
  virtual void enable_assertions() {}
  virtual void finish() {}
};
std::unique_ptr<Engine> make_engine();
}
