#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/uart.h>
#include <zephyr/kernel.h>
#include "zephyr/portability/cmsis_os2.h"
#include "zephyr/sys/slist.h"

/* Define LED, GPIO, and UART nodes from DeviceTree */
#define LED0_NODE DT_ALIAS(led0)
#define LED1_NODE DT_ALIAS(led1)
#define UART1_NODE DT_NODELABEL(usart1)

/* Ensure DeviceTree alias resolution is working */
#if !DT_NODE_EXISTS(LED0_NODE)
#error "LED0_NODE is not defined in DeviceTree!"
#endif

#if !DT_NODE_EXISTS(LED1_NODE)
#error "LED1_NODE is not defined in DeviceTree!"
#endif

/* Create structures for GPIO & USART */
/* static const struct device* usart1; */
static const struct gpio_dt_spec led0 = GPIO_DT_SPEC_GET(LED0_NODE, gpios);
static const struct gpio_dt_spec led1 = GPIO_DT_SPEC_GET(LED1_NODE, gpios);
/* static const struct gpio_dt_spec led1 = GPIO_DT_SPEC_GET(LED1_NODE, gpios); */
static struct k_sem ready_to_blink;

void setup_gpios(void) {
    if (!gpio_is_ready_dt(&led0) || !gpio_is_ready_dt(&led1)) {
        printk("Error: LEDs not ready\n");
        return;
    }
    int ret = gpio_pin_configure_dt(&led0, GPIO_OUTPUT_ACTIVE);
    if (ret < 0) {
        return;
    }

    ret = gpio_pin_configure_dt(&led1, GPIO_OUTPUT_ACTIVE);
    if (ret < 0) {
        return;
    }
}

void toggle_oscillating_leds(int cycleCnt, int delay) {
    gpio_pin_set_dt(&led0, 1);
    gpio_pin_set_dt(&led1, 0);

    for (int i = 0; i < cycleCnt; i++) {
        gpio_pin_toggle_dt(&led0);
        gpio_pin_toggle_dt(&led1);
        osDelay(delay);
        gpio_pin_toggle_dt(&led0);
        gpio_pin_toggle_dt(&led1);
        osDelay(delay);
    }
}

void toggle_combined_leds(int cycleCnt, int delay) {
    gpio_pin_set_dt(&led0, 0);
    gpio_pin_set_dt(&led1, 0);

    for (int i = 0; i < cycleCnt; i++) {
        int ret = gpio_pin_toggle_dt(&led0);
        if (ret < 0) {
            return;
        }
        ret = gpio_pin_toggle_dt(&led1);
        if (ret < 0) {
            return;
        }
        k_msleep(delay);
        ret = gpio_pin_toggle_dt(&led0);
        if (ret < 0) {
            return;
        }
        ret = gpio_pin_toggle_dt(&led1);
        if (ret < 0) {
            return;
        }
        osDelay(5000);
        /* k_msleep(delay); */
    }
}

static osSemaphoreId_t readyToBlink;

/* Background task to blink LEDs */
void blink_leds(void* arg1) {
    /* osSemaphoreAcquire(readyToBlink, osWaitForever); */
    toggle_combined_leds(3, 3000);
    while (1) {
        toggle_oscillating_leds(10, 1000);
        /* gpio_pin_set_dt(&led0, 0); */
        /* gpio_pin_set_dt(&led1, 0); */
        k_msleep(10000);
    }
}

/* Background task for UART testing */
/* void run_console(void* arg1, void* arg2, void* arg3) { */
/*     usart1 = DEVICE_DT_GET(UART1_NODE); */

/*     if (!device_is_ready(usart1)) { */
/*         printk("Error: USART1 not ready\n"); */
/*         gpio_pin_set(led0, DT_GPIO_PIN(LED0_NODE, gpios), 1); */
/*         gpio_pin_set(led1, DT_GPIO_PIN(LED1_NODE, gpios), 1); */
/*         return; */
/*     } */

/*     gpio_pin_set(led0, DT_GPIO_PIN(LED0_NODE, gpios), 1);  // Indicate success */
/*     k_msleep(5000); */

/*     static const char testMsg[] = "USART Test\n"; */
/*     uart_tx(usart1, testMsg, sizeof(testMsg) - 1, SYS_FOREVER_US); */

/*     toggle_oscillating_leds(5, 5000); */
/*     gpio_pin_set(led0, DT_GPIO_PIN(LED0_NODE, gpios), 0); */
/*     gpio_pin_set(led1, DT_GPIO_PIN(LED1_NODE, gpios), 0); */

/*     k_sem_give(&ready_to_blink); */
/* } */

/* K_THREAD_DEFINE(led_thread, 1024, blink_leds, NULL, NULL, NULL, 5, 0, 0); */
/* K_THREAD_DEFINE(console_thread, 1024, run_console, NULL, NULL, NULL, 5, 0, 0); */

typedef struct {
    size_t idx;
    size_t tickDelay;
} blinkArg_t;

static size_t led_thread_cb;

static size_t led_thread_stack[256];

#define STACKSZ         CONFIG_CMSIS_V2_THREAD_MAX_STACK_SIZE
static K_THREAD_STACK_DEFINE(test_stack2, STACKSZ);

static const osThreadAttr_t led_thread_cfg = {
    /* .cb_mem = &led_thread_cb, */
    /* .cb_size = sizeof(led_thread_cb), */
	.stack_mem = &test_stack2,
	.stack_size = STACKSZ,
};


int main(void) {
    static blinkArg_t blinkArgs = {.tickDelay = 1000};

    setup_gpios();
    osStatus_t osSts;
    /* osSts = osKernelInitialize(); */

    readyToBlink = osSemaphoreNew(1, 0, NULL);
    /* CHECK(readyToBlink, return ARM_DRIVER_ERROR); */
    // Create application main thread(s)
    osThreadId_t tId;
    tId = osThreadNew(blink_leds, &blinkArgs, &led_thread_cfg);
    /* CHECK(tId, return -1); */

    osDelay(5000);
    (void)osSemaphoreRelease(readyToBlink);

    osDelay(5000);
    /* osSts = osKernelStart(); */
    /* CHECK(osSts == osOK, return ARM_DRIVER_ERROR); */

    /* for (;;) { */
    /*     __NOP(); */
    /* } */

    /* return 0; */

    /* k_sem_init(&ready_to_blink, 0, 1); */
    /* k_sem_give(&ready_to_blink); */
}
