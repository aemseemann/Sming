cmake_minimum_required(VERSION 3.12)

project(spiffy LANGUAGES C)

set(SMING_HOME "${CMAKE_CURRENT_SOURCE_DIR}/../../Sming" CACHE PATH "Sming Home directory")

add_executable(spiffy
    "${CMAKE_CURRENT_SOURCE_DIR}/spiffy.c"
    "${SMING_HOME}/third-party/spiffs/src/spiffs_cache.c"
    "${SMING_HOME}/third-party/spiffs/src/spiffs_nucleus.c"
    "${SMING_HOME}/third-party/spiffs/src/spiffs_hydrogen.c"
    "${SMING_HOME}/third-party/spiffs/src/spiffs_gc.c"
    "${SMING_HOME}/third-party/spiffs/src/spiffs_check.c"
)
target_include_directories(spiffy PRIVATE
    "${SMING_HOME}/third-party/spiffs/src"
    "${SMING_HOME}/Services/SpifFS"
)

if ("${CMAKE_C_COMPILER_ID}" STREQUAL "GNU" OR "${CMAKE_C_COMPILER_ID}" STREQUAL "Clang")
    target_compile_options(spiffy PRIVATE -Wno-unused-value)
endif()
