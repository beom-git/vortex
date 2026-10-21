#include <vortex2_internal.h>
#include <cstdlib>
#include <dlfcn.h>
#include <string>

namespace {
int (*backend_close)(void*) = nullptr;
int closes = 0;
bool fail_close = false;
}

extern "C" int close_test_count() { return closes; }
extern "C" void close_test_fail(int fail) { fail_close = fail != 0; }
extern "C" vx_queue_h close_test_acquire_queue(vx_device_h device) {
    return vx::to_handle(vx::to_device(device)->legacy_acquire_default_queue());
}

extern "C" int vx_dev_init(callbacks_t* callbacks) {
    const char* backend = std::getenv("VX_CLOSE_TEST_BACKEND");
    if (!backend) return -1;
    std::string library = std::string("libvortex-") + backend + ".so";
    void* handle = dlopen(library.c_str(), RTLD_NOW | RTLD_LOCAL);
    if (!handle) return -1;
    auto init = reinterpret_cast<int (*)(callbacks_t*)>(dlsym(handle, "vx_dev_init"));
    if (!init || init(callbacks)) return -1;
    backend_close = callbacks->dev_close;
    callbacks->dev_close = [](void* context) -> int {
        int status = backend_close(context);
        ++closes;
        return status ? status : (fail_close ? -1 : 0);
    };
    return 0;
}
