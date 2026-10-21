#include <vortex.h>
#include <vortex2.h>
#include <cstdio>
#include <cstdlib>

extern "C" int close_test_count();
extern "C" void close_test_fail(int fail);
extern "C" vx_queue_h close_test_acquire_queue(vx_device_h device);

#define CHECK(condition) do { \
    if (!(condition)) { \
        std::fprintf(stderr, "FAILED at line %d: %s\n", __LINE__, #condition); \
        return 1; \
    } \
} while (0)

int main() {
    const char* backend = std::getenv("VORTEX_DRIVER");
    CHECK(setenv("VX_CLOSE_TEST_BACKEND", backend ? backend : "rtlsim", 1) == 0);
    CHECK(setenv("VORTEX_DRIVER", "close_test", 1) == 0);
    for (int fail = 0; fail < 2; ++fail) {
        close_test_fail(fail);
        vx_device_h device = nullptr;
        CHECK(vx_device_open(0, &device) == VX_SUCCESS);
        CHECK(vx_device_retain(device) == VX_SUCCESS);
        CHECK(vx_device_release(device) == VX_SUCCESS);
        CHECK(close_test_count() == fail);
        CHECK(vx_device_release(device) == (fail ? VX_ERR_DEVICE_LOST : VX_SUCCESS));
        CHECK(close_test_count() == fail + 1);
    }
    vx_device_h device = nullptr;
    CHECK(vx_dev_open(&device) == 0);
    {
        uint8_t data[64] = {};
        vx_buffer_h buffer = nullptr;
        CHECK(vx_mem_alloc(device, sizeof(data), VX_MEM_READ_WRITE, &buffer) == 0);
        CHECK(vx_copy_to_dev(buffer, data, 0, sizeof(data)) == 0);
        CHECK(vx_mem_free(buffer) == 0);
    }
    CHECK(vx_dev_close(device) != 0);
    CHECK(close_test_count() == 3);
    close_test_fail(0);
    CHECK(vx_device_open(0, &device) == VX_SUCCESS);
    vx_buffer_h buffer = nullptr;
    CHECK(vx_buffer_create(device, 64, VX_MEM_READ_WRITE, &buffer) == VX_SUCCESS);
    CHECK(vx_device_release(device) == VX_SUCCESS);
    CHECK(close_test_count() == 3);
    CHECK(vx_buffer_release(buffer) == VX_SUCCESS);
    CHECK(close_test_count() == 4);
    CHECK(vx_device_open(0, &device) == VX_SUCCESS);
    vx_queue_h first = close_test_acquire_queue(device);
    vx_queue_h second = close_test_acquire_queue(device);
    CHECK(first && second);
    CHECK(vx_dev_close(device) == 0);
    CHECK(close_test_count() == 4);
    CHECK(vx_queue_release(first) == VX_SUCCESS);
    CHECK(close_test_count() == 4);
    vx_event_h event = nullptr;
    CHECK(vx_enqueue_barrier(second, 0, nullptr, &event) == VX_SUCCESS);
    CHECK(vx_event_wait_value(event, 1, VX_TIMEOUT_INFINITE) == VX_SUCCESS);
    CHECK(vx_event_release(event) == VX_SUCCESS);
    CHECK(vx_queue_release(second) == VX_SUCCESS);
    CHECK(close_test_count() == 5);
    CHECK(vx_device_open(0, &device) == VX_SUCCESS);
    CHECK(vx_buffer_create(device, 64, VX_MEM_READ_WRITE, &buffer) == VX_SUCCESS);
    CHECK(vx_dev_close(device) == 0);
    CHECK(close_test_count() == 5);
    CHECK(close_test_acquire_queue(device) == nullptr);
    uint8_t data[64] = {};
    CHECK(vx_copy_to_dev(buffer, data, 0, sizeof(data)) != 0);
    CHECK(vx_buffer_release(buffer) == VX_SUCCESS);
    CHECK(close_test_count() == 6);
    std::puts("Device close PASSED");
    return 0;
}
