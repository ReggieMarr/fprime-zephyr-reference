// ======================================================================
// \title  Main.cpp
// \brief main program for the F' application. Intended for CLI-based systems (Linux, macOS)
//
// ======================================================================
// Used to access topology functions
#include <LedBlinker/Top/LedBlinkerTopologyAc.hpp>
#include <LedBlinker/Top/LedBlinkerTopology.hpp>
#include <Fw/Logger/Logger.hpp>

const struct device *serial = DEVICE_DT_GET(DT_NODELABEL(cdc_acm_uart0));

int main()
{
    Os::init();
    Fw::Logger::log("Program Started\n");

    // Object for communicating state to the reference topology
    LedBlinker::TopologyState inputs;
    inputs.dev = serial;
    inputs.uartBaud = 115200;

    // Setup topology
    LedBlinker::setupTopology(inputs);

    while(true)
    {
        rateDriver.cycle();
        k_usleep(1);
    }

    return 0;
}
