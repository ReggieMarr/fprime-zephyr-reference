####
# This sets up the build system for the 'fprime-zephyr-reference' project, including
# components and deployments from project.cmake. In addition, it imports the core F Prime components.
####

cmake_minimum_required(VERSION 3.13)
cmake_policy(SET CMP0048 NEW)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})

project(fprime-zephyr-reference C CXX)

# Get the absolute path of the root of the project
get_filename_component(PROJECT_ROOT "${CMAKE_PROJECT_DIR}../" ABSOLUTE)

set(FPRIME_SETTINGS_FILE "${PROJECT_ROOT}/BaseDeployment/settings.ini")
set(FPRIME_PLATFORM Zephyr)
set(FPRIME_TOOLCHAIN zephyr)

set(CMAKE_TOOLCHAIN_FILE "${PROJECT_ROOT}/deps/fprime-zephyr/cmake/toolchain/zephyr.cmake")

include("${PROJECT_ROOT}/deps/fprime/cmake/FPrime.cmake")

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

add_fprime_subdirectory("${PROJECT_ROOT}/Components")

# This ensures anything pulled in downstream restricts to the Zephyr platform
restrict_platforms(Zephyr)

add_fprime_subdirectory("${CMAKE_CURRENT_LIST_DIR}/Top/")

# This results in creating a new library target based on this module's sources
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

# Links BaseDeployment_Top to zephyr interface library
target_link_libraries(BaseDeployment_Top PUBLIC zephyr_interface)

target_sources(app PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/Main.cpp"
)

generate_zephyr_deployment("Deployment" "app" "${SOURCE_FILES}" "${MOD_DEPS}")

# Use Zephyr's link group mechanism
target_link_libraries(app PUBLIC
    BaseDeployment_Top
)

add_dependencies(app zephyr_generated_headers)

set_target_properties(Svc_FatalHandler PROPERTIES EXCLUDE_FROM_ALL TRUE)
