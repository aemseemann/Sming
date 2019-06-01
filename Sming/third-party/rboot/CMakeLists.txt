# CMakeLists file for rBoot
#
# Can be used either as a stand-alone project or as a subdirectory 
# The build process requires the 'esptool2' utility. 
# If this file is used as a subdirectory, a target of the same name is recognized.
# Otherwise, the location of the tool must be given via the cache variable ESPTOOL2 

cmake_minimum_required(VERSION 3.12)
project(rboot LANGUAGES C)

################################################################################
# Configuration Options
################################################################################

# ROM images must used modified libmain, which includes a routine from rboot
# TODO: could we provide a function/target to create the modified libmain?
option(RBOOT_BIG_FLASH "Enable big flash (>1M) support. A single image can be used for multiple 1MB slots." ON)

option(RBOOT_RTC_ENABLED "Enable rboot<->app communication RTC memory for temporary boot options" OFF)

option(RBOOT_CONFIG_CHKSUM "Use checksum to secure ROM config" OFF)

option(RBOOT_IROM_CHKSUM "Verify checksum of flash rom section." OFF)

set(RBOOT_DELAY_MICROS 0 CACHE STRING "Add a boot delay in microseconds. Allows you time to connect a terminal before rBoot starts to run and output messages.")
set(RBOOT_ROM_OFFSET "0x2000" CACHE INTERNAL "Start address if first ROM after the rboot image and config sector. The same offset is also added to the automatically determined ROM1 start address in order to allow using a single image for flash sizes >= 2MB.")
set(RBOOT_CUSTOM_ROM1_ADDR "" CACHE STRING "Location of the second ROM (ROM1). If left empty, the flash is automatically partitioned into two equally sized areas.")

# GPIO boot options
set(RBOOT_GPIO_MODE off CACHE STRING "Temporarily boot a different rom if the pin RBOOT_GPIO_NUMBER is pulled low during boot. Select 'off' to disable GPIO booting, 'skip' to try the next rom or 'fixed' to boot the ROM located at RBOOT_ROM2_ADDR")
set_property(CACHE RBOOT_GPIO_MODE PROPERTY STRINGS "off" "skip" "fixed")
set(RBOOT_GPIO_NUMBER "16" CACHE STRING "Pin number for RBOOT_GPIO_MODE")
set(RBOOT_GPIO_ROM_ADDR "0x310000" CACHE STRING "Location of the GPIO ROM. This parameter is used only when RBOOT_GPIO_MODE == 'fixed'. If you use two SPIFFS make sure that this address is at least <start_of_SPIFFS_1> + SPIFF_SIZE.")

# build system integration
get_directory_property(build_as_subdirectory PARENT_DIRECTORY)
if (NOT build_as_subdirectory)
    set(RBOOT_INTEGRATION "" CACHE PATH "Location of a customization header named 'rboot-integration.h'.")
endif()

# esptool2 may be provided by the parent directory
if (NOT TARGET esptool2)
    set(ESPTOOL2 "esptool2" CACHE FILEPATH "Path to esptool2 executable.")
    add_executable(esptool2 IMPORTED)
    set_target_properties(esptool2 PROPERTIES IMPORTED_LOCATION "${ESPTOOL2}")
endif()

# advanced options
option(RBOOT_NO_ASM "Activate to use only c code. If you aren't using gcc you may need to do this." OFF)
option(RBOOT_CUSTOM_DEFAULT_CONFIG "[DEFUNCT] Define your own default custom rBoot config, used on first boot and in case of corruption." OFF)
mark_as_advanced(RBOOT_NO_ASM RBOOT_CUSTOM_DEFAULT_CONFIG)

################################################################################
# Build System Description
################################################################################

# overwrite toolchain default optimization settings
add_compile_options(-Os -O3 -Werror -fno-inline-functions -mtext-section-literals)

include_directories("${CMAKE_CURRENT_SOURCE_DIR}")

add_compile_definitions(
    __ets__ 
    ICACHE_FLASH
    # convert cmake config options (RBOOT_...) to defines (BOOT_...)
    $<$<BOOL:${RBOOT_BIG_FLASH}>:BOOT_BIG_FLASH>
    $<$<STREQUAL:${RBOOT_DELAY_MICROS},"">:BOOT_DELAY_MICROS=${RBOOT_DELAY_MICROS}>
    $<$<BOOL:${RBOOT_RTC_ENABLED}>:BOOT_RTC_ENABLED>
    $<$<BOOL:${RBOOT_CONFIG_CHKSUM}>:BOOT_CONFIG_CHKSUM>
    $<$<BOOL:${RBOOT_IROM_CHKSUM}>:BOOT_IROM_CHKSUM>
    $<$<STREQUAL:${RBOOT_CUSTOM_ROM1_ADDR},"">:BOOT_ROM1_ADDR=${RBOOT_CUSTOM_ROM1_ADDR}>
    $<$<STREQUAL:${RBOOT_GPIO_ROM_ADDR},"">:BOOT_ROM2_ADDR=${RBOOT_GPIO_ROM_ADDR}>    
    $<$<BOOL:${RBOOT_NO_ASM}>:BOOT_NO_ASM>
)

if (NOT RBOOT_GPIO_MODE STREQUAL "off")
    add_compile_definitions(
        $<IF:$<STREQUAL:${RBOOT_GPIO_MODE},"skip">,BOOT_GPIO_SKIP_ENABLED,BOOT_GPIO_ENABLED>
        $<$<STREQUAL:${RBOOT_GPIO_NUMBER},"">:BOOT_GPIO_NUM=${RBOOT_GPIO_NUMBER}>
    )
endif()

if (NOT "${RBOOT_INTEGRATION}" STREQUAL "")
    add_compile_definitions(RBOOT_INTEGRATION)
    include_directories("${RBOOT_INTEGRATION}")
endif()

# create stage2a (RAM loader part)
add_executable(rboot-stage2a 
    rboot-stage2a.c 
    rboot-private.h
    rboot.h
)
set(STAGE2A_LINKER_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/rboot-stage2a.ld")
# TODO: check if -u call_user_start is needed (links without)
target_link_options(rboot-stage2a PRIVATE "-T${STAGE2A_LINKER_SCRIPT}" -Wl,--no-check-sections "SHELL:-u call_user_start")
set_target_properties(rboot-stage2a PROPERTIES LINK_DEPENDS "${STAGE2A_LINKER_SCRIPT}")

add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/rboot-hex2a.h"
    DEPENDS "$<TARGET_FILE:rboot-stage2a>"
    COMMAND esptool2 -quiet -header "$<TARGET_FILE:rboot-stage2a>" "${CMAKE_CURRENT_BINARY_DIR}/rboot-hex2a.h" .text
    COMMENT "Preparing rboot stage-2a binary for inclusion into rboot"
)

# create stage2 loader (rboot)
add_executable(rboot
    rboot.c
    rboot-private.h 
    rboot.h 
    "${CMAKE_CURRENT_BINARY_DIR}/rboot-hex2a.h"
)
add_dependencies(rboot rboot-stage2a)

target_include_directories(rboot PRIVATE "${CMAKE_CURRENT_BINARY_DIR}") # to find rboot-hex2a.h
set_property(SOURCE rboot.c PROPERTY OBJECT_DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/rboot-hex2a.h") # help cmake dependency tracking (In theory, this should not be necessary, but it does fail sometimes.)
# TODO: check if -u call_user_start is needed (links without)
target_link_options(rboot PRIVATE "-Teagle.app.v6.ld" -Wl,--no-check-sections "SHELL:-u call_user_start")
# Omit dependency on linker script provided by toolchain

# add image extraction via esptool2 as a post-build step
set(RBOOT_IMAGE_FILE "${CMAKE_CURRENT_BINARY_DIR}/rboot.bin")
add_custom_command(TARGET rboot POST_BUILD
    # It is not necessary to specify flash configuration options to esptool2, since esptool.py will override them anyway when flashing to adress 0x0000.
    COMMAND esptool2 -quiet -bin -boot0 "$<TARGET_FILE:rboot>" "${RBOOT_IMAGE_FILE}" .text .rodata
    # TODO: add image_info output with esptool
    COMMENT "Create rboot image"
)
set_target_properties(rboot PROPERTIES IMAGE_FILE "${RBOOT_IMAGE_FILE}")


# library for applications to link to in order to communicate with rboot
add_library(rboot-appcode STATIC EXCLUDE_FROM_ALL # only build on request
    appcode/rboot-api.c
    appcode/rboot-api.h
    appcode/rboot-bigflash.c
)
