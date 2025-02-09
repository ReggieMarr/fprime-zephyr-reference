####
# This sets up the build system for the 'fprime-zephyr-reference' project, including
# components and deployments from project.cmake. In addition, it imports the core F Prime components.
####

cmake_minimum_required(VERSION 3.20)
cmake_policy(SET CMP0048 NEW)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})

###
# F' Core Setup
# This includes all of the F prime core components, and imports the make-system.
###
# set(FPRIME_SKIP_TOOLS_VERSION_CHECK ON)
# set(FPRIME_FRAMEWORK_PATH "${CMAKE_CURRENT_LIST_DIR}/fprime" CACHE PATH "Location of F prime framework" FORCE)
# set(FPRIME_PROJECT_ROOT "${CMAKE_CURRENT_LIST_DIR}" CACHE PATH "Root path of F prime project" FORCE)
# NOTE: register custom targets between these two lines

# set(SYSCALL_LIST_H "${CMAKE_BINARY_DIR}/zephyr/include/generated/zephyr/syscall_list.h")
# set(PARSE_SYSCALLS_JSON "${CMAKE_BINARY_DIR}/misc/generated/syscalls.json")
# set(PARSE_SYSCALLS_TARGET parse_syscalls)

# # Step 3: Wait for `parse_syscalls.json`, ensuring it's generated first
# add_custom_target(generate_syscalls
#     COMMAND ${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR} --target ${PARSE_SYSCALLS_TARGET}
#     COMMENT "Ensuring Zephyr syscall parsing completes before F′ builds."
# )

# add_custom_target(wait_for_syscalls
#     COMMAND ${CMAKE_COMMAND} -E sleep 1
#     DEPENDS ${PARSE_SYSCALLS_JSON} ${SYSCALL_LIST_H}
# )

# include("${FPRIME_FRAMEWORK_PATH}/cmake/FPrime-Code.cmake")
project(fprime-zephyr-reference C CXX)


set(CMAKE_VERBOSE_MAKEFILE ON)

include("${CMAKE_CURRENT_LIST_DIR}/fprime/cmake/FPrime.cmake")
fprime_setup_included_code()


# This includes project-wide objects
include("${CMAKE_CURRENT_LIST_DIR}/project.cmake")

message(STATUS "OS Implementation Library: ${OS_IMPL_LIB}")
message(STATUS "Link Libraries: ${TARGET_LINK_LIBRARIES}")

