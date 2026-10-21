#include <rtlsim.h>
#include "engine.h"
#include "bridge.h"
#include <cout_drainer.h>

using namespace vortex;

class Processor::Impl {
public:
  Bridge bridge;
  std::unique_ptr<Engine> engine;

  Impl() {
    bridge.activate();
    engine = make_engine();
    execute(Bridge::Reset);
    engine->enable_assertions();
  }

  void execute(Bridge::Command command, uint32_t address = 0, uint32_t data = 0) {
    bridge.activate();
    bridge.submit(command, address, data);
    while (!bridge.done) {
      engine->step();
    }
  }
};

Processor::Processor() : impl_(new Impl()) {}
Processor::~Processor() { delete impl_; }
void Processor::attach_ram(RAM* ram) { impl_->bridge.ram = ram; }
void Processor::finish() { impl_->engine->finish(); }

void Processor::run(HostMonitor* monitor, CoutDrainer* drainer) {
  impl_->bridge.monitor = monitor;
  impl_->bridge.drainer = drainer;
  impl_->execute(Bridge::Run);
  if (drainer) {
    drainer->tick();
  }
  impl_->bridge.monitor = nullptr;
  impl_->bridge.drainer = nullptr;
}

int Processor::dcr_write(uint32_t address, uint32_t value) {
  impl_->execute(Bridge::Write, address, value);
  return 0;
}

int Processor::dcr_read(uint32_t address, uint32_t tag, uint32_t* value) {
  impl_->execute(Bridge::Read, address, tag);
  *value = impl_->bridge.result;
  return 0;
}
