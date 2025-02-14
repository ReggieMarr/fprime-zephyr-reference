// ======================================================================
// \title  LedBlinkerTopology.cpp
// \brief cpp file containing the topology instantiation code
//
// ======================================================================
// Provides access to autocoded functions
#include <LedBlinker/Top/LedBlinkerTopologyAc.hpp>
#include <config/FppConstantsAc.hpp>

// Necessary project-specified types
#include <Svc/FramingProtocol/FprimeProtocol.hpp>
#include "Zephyr/Fw/ZephyrAllocator/ZephyrAllocator.hpp"

#include <zephyr/drivers/gpio.h>

static const struct gpio_dt_spec led_pin = GPIO_DT_SPEC_GET(DT_ALIAS(led0), gpios);

// The reference topology uses the F´ packet protocol when communicating with the ground and therefore uses the F´
// framing and deframing implementations.
static Svc::FprimeFraming framing;
static Svc::FprimeDeframing deframing;

// The reference topology divides the incoming clock signal (1kHz) into sub-signals: 10Hz
static Svc::RateGroupDriver::DividerSet rateGroupDivisors = {{
    { static_cast<NATIVE_INT_TYPE>(LedBlinker::FppConstant_RATE_1KHZ_DIVISOR::RATE_1KHZ_DIVISOR), 0 },
    { static_cast<NATIVE_INT_TYPE>(LedBlinker::FppConstant_RATE_10KHZ_DIVISOR::RATE_10KHZ_DIVISOR), 0 }
}};



// Rate groups may supply a context token to each of the attached children whose purpose is set by the project. The
// reference topology sets each token to zero as these contexts are unused in this project.
static NATIVE_INT_TYPE rateGroup1KhzContext[FppConstant_PassiveRateGroupOutputPorts::PassiveRateGroupOutputPorts] = {};
static NATIVE_INT_TYPE rateGroup10KhzContext[FppConstant_PassiveRateGroupOutputPorts::PassiveRateGroupOutputPorts] = {};

static const size_t COM_BUFFER_SIZE = 128;
static const size_t COM_BUFFER_COUNT = 3;
static const size_t BUFFER_MANAGER_ID = 200;

static const FwSizeType COMM_PRIORITY = 49;
// bufferManager constants
static const FwSizeType FRAMER_BUFFER_SIZE = FW_MAX(FW_COM_BUFFER_MAX_SIZE, FW_FILE_BUFFER_MAX_SIZE + sizeof(U32)) +
                                             Svc::FpFrameHeader::SIZE;
static const FwSizeType FRAMER_BUFFER_COUNT = 30;
static const FwSizeType DEFRAMER_BUFFER_SIZE = FW_MAX(FW_COM_BUFFER_MAX_SIZE, FW_FILE_BUFFER_MAX_SIZE + sizeof(U32));
static const FwSizeType DEFRAMER_BUFFER_COUNT = 30;
static const FwSizeType COM_DRIVER_BUFFER_SIZE = 3000;
static const FwSizeType COM_DRIVER_BUFFER_COUNT = 30;

static Fw::ZephyrAllocator mallocator;

/**
 * \brief configure/setup components in project-specific way
 *
 * This is a *helper* function which configures/sets up each component requiring project specific input. This includes
 * allocating resources, passing-in arguments, etc. This function may be inlined into the topology setup function if
 * desired, but is extracted here for clarity.
 */
static void configureTopology() {
    // Command sequencer needs to allocate memory to hold contents of command sequences
    // Rate group driver needs a divisor list
    LedBlinker::rateGroupDriver.configure(rateGroupDivisors);

    // Rate groups require context arrays.
    LedBlinker::rateGroup1Khz.configure(rateGroup1KhzContext, FW_NUM_ARRAY_ELEMENTS(rateGroup1KhzContext));
    LedBlinker::rateGroup10Khz.configure(rateGroup10KhzContext, FW_NUM_ARRAY_ELEMENTS(rateGroup10KhzContext));

    Svc::BufferManager::BufferBins buffMgrBins;
    std::memset(&buffMgrBins, 0, sizeof(buffMgrBins));

    buffMgrBins.bins[0].bufferSize = FRAMER_BUFFER_SIZE;
    buffMgrBins.bins[0].numBuffers = FRAMER_BUFFER_COUNT;
    buffMgrBins.bins[1].bufferSize = DEFRAMER_BUFFER_SIZE;
    buffMgrBins.bins[1].numBuffers = DEFRAMER_BUFFER_COUNT;
    buffMgrBins.bins[2].bufferSize = COM_DRIVER_BUFFER_SIZE;
    buffMgrBins.bins[2].numBuffers = COM_DRIVER_BUFFER_COUNT;

    LedBlinker::bufferManager.setup(BUFFER_MANAGER_ID, 0, mallocator, buffMgrBins);

    // Framer and Deframer components need to be passed a protocol handler
    LedBlinker::framer.setup(framing);
    LedBlinker::deframer.setup(deframing);
}

// Public functions for use in main program are namespaced with deployment name LedBlinker
namespace LedBlinker {
void setupTopology(const TopologyState& state) {
    configureTopology();

    setup(state);

    // Configure GPIO pins
    gpioDriver.open(led_pin, Zephyr::ZephyrGpioDriver::GpioDirection::OUT);

    // Configure hardware rate driver
    rateDriver.configure(LedBlinker::FppConstant_RATE_INTERVAL_MS::RATE_INTERVAL_MS);
    // Configure StreamDriver / UART
    commDriver.configure(state.dev, state.uartBaud);

    // Start hardware rate driver
    rateDriver.start();
}

};  // namespace LedBlinker
