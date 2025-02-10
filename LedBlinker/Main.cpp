// ======================================================================
// \title  Main.cpp
// \brief main program for the F' application. Intended for CLI-based systems (Linux, macOS)
//
// ======================================================================
// Used to access topology functions
#include <LedBlinker/Top/LedBlinkerTopologyAc.hpp>
#include <LedBlinker/Top/LedBlinkerTopology.hpp>
#include <Fw/Logger/Logger.hpp>
#include <zephyr/kernel.h>

// const struct device *serial = DEVICE_DT_GET(DT_NODELABEL(cdc_acm_uart0));
/* 1000 msec = 1 sec */
#define SLEEP_TIME_MS   1000

void __attribute__((weak, long_call)) run(void) {
    k_msleep(SLEEP_TIME_MS);
}

int main()
{
    Os::init();
	while (1) {
        run();
	}

    return 0;
}
