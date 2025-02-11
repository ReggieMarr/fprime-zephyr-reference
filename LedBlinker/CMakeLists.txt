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
# register_fprime_deployment()
# register_fprime_module()


# Links LedBlinker_Top to zephyr interface library
target_link_libraries(LedBlinker_Top PUBLIC zephyr_interface)


# include("${FPRIME_FRAMEWORK_PATH}/cmake/target/build.cmake")
include("/fprime-zephyr-reference/fprime/cmake/target/build.cmake")
function(generate_zephyr_deployment TARGET_TYPE TARGET_NAME SOURCE_FILES DEPENDENCIES)
    get_nearest_build_root(${CMAKE_CURRENT_LIST_DIR})
    set_property(GLOBAL PROPERTY MODULE_DETECTION TRUE)

    # The function this is based off of would call add_executable or add_library here
    # but zephyr handles this for us already

    # Modules properties for posterity
    set_target_properties("${TARGET_NAME}" PROPERTIES FP_TYPE "${TARGET_TYPE}")
    set_property(GLOBAL APPEND PROPERTY FPRIME_MODULES "${TARGET_NAME}")

    message(STATUS "Setup sources for ${TARGET_NAME} ${SOURCE_FILES}")
    # setup_module_targets("${TARGET_NAME}" "${SOURCE_FILES}" "${DEPENDENCIES}")
    setup_single_target("build" "${TARGET_NAME}" "${SOURCE_FILES}" "${DEPENDENCIES}")

    # get_target_property(RECURSIVE_DEPENDENCIES "${MODULE}" FP_RECURSIVE_DEPS)

    # cmake_language(CALL "${TARGET_NAME}_add_deployment_target" "${MODULE}" "${TARGET_NAME}" "${SOURCES}" "${DEPENDENCIES}" "${RECURSIVE_DEPENDENCIES}")
    # build_add_deployment_target("Deployment" "${MODULE}" "${TARGET_NAME}" "${SOURCES_FILES}" "${DEPENDENCIES}" "${RECURSIVE_DEPENDENCIES}")

endfunction(generate_zephyr_deployment)

target_sources(app PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/Main.cpp"
)

generate_zephyr_deployment("Deployment" "zephyr_final" "${SOURCE_FILES}" "${MOD_DEPS}")

# Use Zephyr's link group mechanism
target_link_libraries(app PUBLIC
    LedBlinker_Top
)

set_target_properties(Svc_FatalHandler PROPERTIES EXCLUDE_FROM_ALL TRUE)
