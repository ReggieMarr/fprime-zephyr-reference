####
# This sets up the build system for the 'fprime-zephyr-reference' project, including
# components and deployments from project.cmake. In addition, it imports the core F Prime components.
####

cmake_minimum_required(VERSION 3.20)
cmake_policy(SET CMP0048 NEW)

# set(BOARD teensy41)
# set(BOARD_QUALIFIERS /mimxrt1062)
# set(BOARD "sam_v71_xult")
# set(BOARD_QUALIFIERS "samv71q21b")
find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})

project(fprime-zephyr-reference C CXX)

set(FPRIME_ENABLE_FRAMEWORK_UTS OFF)
set(FPRIME_ENABLE_AUTOCODER_UTS OFF)
set(FPRIME_FRAMEWORK_PATH /fprime-zephyr-reference/fprime)
set(FPRIME_PROJECT_ROOT /fprime-zephyr-reference)
set(FPRIME_SETTINGS_FILE /fprime-zephyr-reference/settings.ini)
set(FPRIME_ENVIRONMENT_FILE /fprime-zephyr-reference/settings.ini)
set(FPRIME_CONFIG_DIR /fprime-zephyr-reference/config)
set(FPRIME_INSTALL_DEST /fprime-zephyr-reference/build-artifacts)

set(FPRIME_PLATFORM Zephyr)

set(FPRIME_TOOLCHAIN zephyr)
set(CMAKE_TOOLCHAIN_FILE /fprime-zephyr-reference/fprime-zephyr/cmake/toolchain/zephyr.cmake)
set(FPRIME_LIBRARY_LOCATIONS /fprime-zephyr-reference/fprime-zephyr;/fprime-zephyr-reference/fprime-baremetal)

set(CMAKE_VERBOSE_MAKEFILE ON)

# add_compile_options(
#     -fno-exceptions
#     -fno-rtti
#     -fno-builtin
# )
# add_link_options(
#     -nostdlib
#     -Wl,--gc-sections
#     # Use only one of libstdc++ or libm, not both
#     -nodefaultlibs
# )

include("${CMAKE_CURRENT_LIST_DIR}/fprime/cmake/FPrime.cmake")

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

