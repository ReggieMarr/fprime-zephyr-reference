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

# This results in creating a new library target based on this module's sources
register_fprime_module()

include("${FPRIME_FRAMEWORK_PATH}/cmake/target/build.cmake")
function(generate_zephyr_deployment TARGET_TYPE TARGET_NAME SOURCE_FILES DEPENDENCIES)
    get_nearest_build_root(${CMAKE_CURRENT_LIST_DIR})
    set_property(GLOBAL PROPERTY MODULE_DETECTION TRUE)

    # The function this is based off of would call add_executable or add_library here
    # but zephyr handles this for us already

    # Modules properties for posterity
    set_target_properties("${TARGET_NAME}" PROPERTIES
        IS_DEPLOYMENT_LIB TRUE
        FP_TYPE "Deployment"
    )
    set_property(GLOBAL APPEND PROPERTY FPRIME_MODULES ${TARGET_NAME})

    setup_single_target("build" "${TARGET_NAME}" "${SOURCE_FILES}" "${DEPENDENCIES}")
endfunction(generate_zephyr_deployment)

# Links LedBlinker_Top to zephyr interface library
target_link_libraries(LedBlinker PUBLIC zephyr_interface)

target_sources(app PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/Main.cpp"
)

generate_zephyr_deployment("Deployment" "app" "${SOURCE_FILES}" "${MOD_DEPS}")

# Use Zephyr's link group mechanism
target_link_libraries(app PUBLIC
    LedBlinker
)

set_target_properties(Svc_FatalHandler PROPERTIES EXCLUDE_FROM_ALL TRUE)
