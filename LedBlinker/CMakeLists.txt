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
# set(SOURCE_FILES "${CMAKE_CURRENT_LIST_DIR}/Launch.cpp")
set(MOD_DEPS ${FPRIME_CURRENT_MODULE}/Top)
register_fprime_deployment()

# add_library(LedBlinker_Combined STATIC
#     $<TARGET_OBJECTS:LedBlinker>  # Get objects from executable
#     "${CMAKE_CURRENT_LIST_DIR}/Stub.cpp"
# )

# target_link_libraries(LedBlinker_Combined
#     PUBLIC
#         LedBlinker_Top
#         Os_Console_Zephyr
#         Os_Task_Zephyr
#         Os_Queue_Zephyr
#         Os_Mutex_Zephyr
#         Os_RawTime_Zephyr
#         Os_Zephyr_Shared
# )

# target_link_libraries(zephyr
#     PUBLIC
#         $<TARGET_OBJECTS:LedBlinker>  # Get objects from executable
#         LedBlinker_Top
#         Os_Console_Zephyr
#         Os_Task_Zephyr
#         Os_Queue_Zephyr
#         Os_Mutex_Zephyr
#         Os_RawTime_Zephyr
#         Os_Zephyr_Shared
# )

target_sources(app PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/Main.cpp"
)
target_link_libraries(LedBlinker PRIVATE
    -lstdc++           # C++ runtime
    ${ZEPHYR_LINK_OPTIONS}
    -Wl,--start-group
    -Wl,--whole-archive
    LedBlinker_Top
    -Wl,--no-whole-archive
    -Wl,--end-group
)

# target_link_directories(app PRIVATE
#     "${CMAKE_CURRENT_LIST_DIR}/Top/"
# )

# FILE(GLOB app_sources Main.cpp)
# target_sources(app PRIVATE ${app_sources})

# target_link_libraries(LedBlinker PRIVATE
#     -lstdc++           # C++ runtime
#     ${ZEPHYR_LINK_OPTIONS}
#     -Wl,--start-group
#     -Wl,--whole-archive
#     # Os_Mutex_Zephyr
#     # Os_Task_Zephyr
#     zephyr_interface
#     zephyr
#     -Wl,--no-whole-archive
#     -Wl,--end-group
# )

set_target_properties(Svc_FatalHandler PROPERTIES EXCLUDE_FROM_ALL TRUE)


function(print_target_properties tgt)
    if(NOT TARGET ${tgt})
        message("No target '${tgt}'")
        return()
    endif()

    # Get all properties that are set
    execute_process(COMMAND cmake --help-property-list OUTPUT_VARIABLE CMAKE_PROPERTY_LIST)
    string(REGEX REPLACE "[\n\r]" ";" CMAKE_PROPERTY_LIST "${CMAKE_PROPERTY_LIST}")

    message("Configuration for target ${tgt}")
    foreach(prop ${CMAKE_PROPERTY_LIST})
        string(REPLACE "<CONFIG>" "${CMAKE_BUILD_TYPE}" prop ${prop})
        # Fix https://stackoverflow.com/questions/32197663/how-can-i-remove-the-property-debuggercommand-from-the-target
        if(prop STREQUAL "LOCATION" OR prop MATCHES "^LOCATION_" OR prop MATCHES "_LOCATION$")
            continue()
        endif()
        get_property(propval TARGET ${tgt} PROPERTY ${prop} SET)
        if(propval)
            get_target_property(propval ${tgt} ${prop})
            message(STATUS "${prop} = ${propval}")
        endif()
    endforeach()
    message("")
endfunction()

# Use it like this:

message("--------------------LEDBLINKER--------------------------")

print_target_properties(LedBlinker)

message("--------------------LEDBLINKER_TOP--------------------------")
print_target_properties(LedBlinker_Top)
