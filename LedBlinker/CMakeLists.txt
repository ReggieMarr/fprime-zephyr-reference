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

target_link_directories(app PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/Top/"
)

# FILE(GLOB app_sources Main.cpp)
# target_sources(app PRIVATE ${app_sources})

# target_link_libraries(app PRIVATE
#     -Wl,--whole-archive
#     LedBlinker_Combined
#     -Wl,--no-whole-archive
# )

set_target_properties(Svc_FatalHandler PROPERTIES EXCLUDE_FROM_ALL TRUE)

# target_link_libraries(app PRIVATE LedBlinker_Top)
# target_link_libraries(LedBlinker_Top PRIVATE Os_Zephyr_Shared)
# add_dependencies(zephyr_final
#         $<TARGET_OBJECTS:LedBlinker>  # Get objects from executable
#         LedBlinker_Top)

target_link_libraries(LedBlinker_Top PRIVATE
    -Wl,--whole-archive
    zephyr
    -Wl,--no-whole-archive
)

add_dependencies(LedBlinker zephyr_final)
