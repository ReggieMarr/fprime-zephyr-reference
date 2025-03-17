####
# This sets up the build system for the 'fprime-zephyr-reference' project, including
# components and deployments from project.cmake. In addition, it imports the core F Prime components.
####

cmake_minimum_required(VERSION 3.13)
cmake_policy(SET CMP0048 NEW)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})

project(fprime-zephyr-reference C CXX)

###
# F' Core Setup
# This includes all of the F prime core components, and imports the make-system.
###
set(FPRIME_SETTINGS_FILE /fprime-zephyr-reference/settings.ini)
set(FPRIME_ENVIRONMENT_FILE /fprime-zephyr-reference/settings.ini)
set(FPRIME_PLATFORM Zephyr)
set(FPRIME_TOOLCHAIN zephyr)

set(CMAKE_TOOLCHAIN_FILE /fprime-zephyr-reference/deps/fprime-zephyr/cmake/toolchain/zephyr.cmake)

include("${CMAKE_CURRENT_LIST_DIR}/deps/fprime/cmake/FPrime.cmake")

# Basically we just want to avoid the install target and util targets
set(FPRIME_SUB_BUILD_TARGETS
    target/build    # TODO add our custom build target here
    autocoder/fpp
    autocoder/ai_xml
    autocoder/packets
    target/version
    target/sbom
)

fprime_setup_included_code()


# This includes project-wide objects
include("${CMAKE_CURRENT_LIST_DIR}/project.cmake")
