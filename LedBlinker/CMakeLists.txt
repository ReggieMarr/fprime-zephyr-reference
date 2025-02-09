#####
# 'LedBlinker' Deployment:
#
# This registers the 'LedBlinker' deployment to the build system. 
# Custom components that have not been added at the project-level should be added to 
# the list below.
#
#####

# Deployment is only compatible with the Zephyr platform
restrict_platforms(Zephyr)

###
# Topology and Components
###
add_fprime_subdirectory("${CMAKE_CURRENT_LIST_DIR}/Top/")

# Add custom components to this specific deployment here
# add_fprime_subdirectory("${CMAKE_CURRENT_LIST_DIR}/MyComponent/")


set(SOURCE_FILES "${CMAKE_CURRENT_LIST_DIR}/Stub.cpp")
set(MOD_DEPS ${FPRIME_CURRENT_MODULE}/Top)

register_fprime_deployment()

# add_dependencies(ZephyrRef syscall_list)

FILE(GLOB app_sources Main.cpp)
target_sources(app PRIVATE ${app_sources})
target_link_libraries(app PRIVATE LedBlinker_Top)
# add_dependencies(LedBlinker zephyr_final)

# # Step 2: Explicit Target for Syscall Generation
# add_custom_target(generate_syscalls
#     COMMAND ${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR} --target syscall_list
#     COMMENT "Ensuring Zephyr syscalls are generated before F′ builds."
# )

# # Step 3: Make F′ Depend on the Syscall Generation
# add_dependencies(generate_syscalls syscall_list)

# # Step 4: Ensure F′ Waits for `generate_syscalls`
# include_directories(
#     ${ZEPHYR_BASE}/include
#     ${CMAKE_BINARY_DIR}/zephyr/include/generated
# )
# add_custom_target(wait_for_syscalls
#     COMMAND ${CMAKE_COMMAND} -E sleep 1  # Prevents race conditions
#     DEPENDS ${CMAKE_BINARY_DIR}/zephyr/include/generated/zephyr/syscall_list.h
# )
# add_dependencies(LedBlinker generate_syscalls wait_for_syscalls)

set(CMAKE_VERBOSE_MAKEFILE ON)

# set_target_properties(Svc_FatalHandler PROPERTIES EXCLUDE_FROM_ALL TRUE) # Temporary to fix bug in F Prime Release v3.5.0

