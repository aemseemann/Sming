cmake_minimum_required(VERSION 3.12)

project(esptool2 LANGUAGES C)

add_executable(esptool2
    "${CMAKE_CURRENT_SOURCE_DIR}/esptool2.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/esptool2_elf.c"
)
target_include_directories(esptool2 PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
