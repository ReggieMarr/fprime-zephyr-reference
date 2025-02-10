#####
# 'LedBlinker' Deployment:
#
# This registers the 'LedBlinker' deployment to the build system. 
# Custom components that have not been added at the project-level should be added to 
# the list below.
#
#####

restrict_platforms(Zephyr)

add_fprime_subdirectory("${CMAKE_CURRENT_LIST_DIR}/Top/")
set(SOURCE_FILES "${CMAKE_CURRENT_LIST_DIR}/Stub.cpp")
set(MOD_DEPS ${FPRIME_CURRENT_MODULE}/Top)
# set(MOD_DEPS ${PROJECT_NAME}/Top)
# register_fprime_deployment()

# This results in creating a new library target based on this module's sources
register_fprime_module()

# Check if this gets called otherwise we might need to call the next line manually
if (TARGET "${FPRIME_CURRENT_MODULE}")
    message(STATUS "Created target for ${FPRIME_CURRENT_MODULE}")
else()
    message(ERROR "FAILED to create target for ${FPRIME_CURRENT_MODULE}")
endif()
# add_dependencies("${FPRIME_CURRENT_MODULE}" config)


# Links LedBlinker_Top to zephyr interface library
target_link_libraries(LedBlinker PUBLIC zephyr_interface)

function(generate_zephyr_deployment TARGET_TYPE TARGET_NAME SOURCE_FILES DEPENDENCIES)
    get_nearest_build_root(${CMAKE_CURRENT_LIST_DIR})
    set_property(GLOBAL PROPERTY MODULE_DETECTION TRUE)

    # The function this is based off of would call add_executable or add_library here
    # but zephyr handles this for us already

    # Modules properties for posterity
    set_target_properties("${TARGET_NAME}" PROPERTIES FP_TYPE "${TARGET_TYPE}")
    set_property(GLOBAL APPEND PROPERTY FPRIME_MODULES "${TARGET_NAME}")

    setup_module_targets("${TARGET_NAME}" "${SOURCE_FILES}" "${DEPENDENCIES}")
endfunction(generate_base_module_properties)

generate_zephyr_deployment("Deployment" "zephyr" "${SOURCE_FILES}" "${MOD_DEPS}")

target_sources(app PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/Main.cpp"
)

# Use Zephyr's link group mechanism
target_link_libraries(app PUBLIC
    LedBlinker
)

set_target_properties(Svc_FatalHandler PROPERTIES EXCLUDE_FROM_ALL TRUE)
