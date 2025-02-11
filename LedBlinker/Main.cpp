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

// void __attribute__((weak, long_call)) run(void) {
//     k_msleep(SLEEP_TIME_MS);
// }

// int main()
// {
//     Os::init();
// 	while (1) {
//         run();
// 	}

//     return 0;
// }

// const struct device *serial = DEVICE_DT_GET(DT_NODELABEL(cdc_acm_uart0));
const struct device *serial = DEVICE_DT_GET(DT_CHOSEN(zephyr_console));
// static const struct pwm_dt_spec pwm_led0 = PWM_DT_SPEC_GET(DT_ALIAS(pwm_led0));

#define LED0_NODE DT_ALIAS(led0)
#define LED1_NODE DT_ALIAS(led1)
static const struct gpio_dt_spec led0 = GPIO_DT_SPEC_GET(LED0_NODE, gpios);
static const struct gpio_dt_spec led1 = GPIO_DT_SPEC_GET(LED1_NODE, gpios);

int main(void)
{
	int ret;
	bool led_state = true;

	if (!gpio_is_ready_dt(&led0)) {
		return 0;
	}

	ret = gpio_pin_configure_dt(&led0, GPIO_OUTPUT_ACTIVE);
	if (ret < 0) {
		return 0;
	}

    gpio_pin_configure_dt(&led1, GPIO_OUTPUT_ACTIVE);
    gpio_pin_set_dt(&led1, 1);

    Os::init();
    Fw::Logger::log("Program Started\n");

    // Object for communicating state to the reference topology
    LedBlinker::TopologyState inputs;
    inputs.dev = serial;
    inputs.uartBaud = 115200;
    // Setup topology
    LedBlinker::setupTopology(inputs);
        k_usleep(1000);

	while (1) {
		ret = gpio_pin_toggle_dt(&led0);
		if (ret < 0) {
			return 0;
		}
		ret = gpio_pin_toggle_dt(&led1);
		if (ret < 0) {
			return 0;
		}

		led_state = !led_state;
		printf("LED state: %s\n", led_state ? "ON" : "OFF");
		k_msleep(SLEEP_TIME_MS);
	}

    // while(true)
    // {
    //     gpio_pin_toggle_dt(&led0);
    //     gpio_pin_toggle_dt(&led1);
    //     rateDriver.cycle();
    //     k_usleep(1);
    // }

    return 0;
}
