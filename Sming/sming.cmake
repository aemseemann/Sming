# Main cmake file provided for projects using SMING
# 
# In your main project CMakeLists.txt, do the following:
# - include(sming.cmake)
# - use the sming_... functions, to create a firmware image, filesystem, etc.
#
include_guard(GLOBAL)

# enforce c++11
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# pull in sming framework and its cache variables (config options, e. g. SDK_BASE)
add_subdirectory(${CMAKE_CURRENT_LIST_DIR} sming)

# Python2 is required for memanalyzer and also esptool.py on non-windows hosts
find_package(Python2 COMPONENTS Interpreter)

if (CMAKE_HOST_SYSTEM_NAME MATCHES "(FreeBSD)")
    set(COM_PORT_INIT /dev/cuaU0)    
elseif(CMAKE_HOST_APPLE)
    set(COM_PORT_INIT /dev/tty.usbserial)
elseif(CMAKE_HOST_WIN32)
    set(COM_PORT_INIT COM3)
elseif(CMAKE_HOST_UNIX)
    set(COM_PORT_INIT /dev/ttyUSB0)
else()
    message(FATAL_ERROR "Operating system not supported: ${CMAKE_HOST_SYSTEM_NAME}")
endif()

set(COM_PORT "${COM_PORT_INIT}" CACHE STRING "Serial port for programming and communication with ESP device.")
# COM_SPEED_SERIAL is defined in Sming's CMakeLists.txt
set(COM_SPEED_ESPTOOL "${COM_SPEED_SERIAL}" CACHE STRING "Baud rate for esptool (writing flash, etc.)")

if (CMAKE_HOST_SYSTEM_WIN32)
    set(SDK_TOOLS "${SDK_BASE}/../tools")
    set(ESPTOOL "${SDK_TOOLS}/ESP8266/esptool.exe" CACHE FILEPATH "Path to esptool.exe from SDK")
    set(KILL_TERM taskkill.exe -f -im Terminal.exe || exit 0)
    set(TERMINAL "${SDK_TOOLS}/Terminal.exe" CACHE FILEPATH "Path to a terminal program (invoked as <TERMINAL> COM_PORT BAUD_RATE)")
    set(TERMINAL "${TERMINAL}" ${COM_PORT} ${COM_SPEED_SERIAL})
else()
    set(ESPTOOL "${SDK_BASE}/../esptool/esptool.py" CACHE FILEPATH "Path to esptool.py from SDK")
    set(ESPTOOL "${Python2_EXECUTABLE}" "${ESPTOOL}")
    set(KILL_TERM pkill -9 -f "${COM_PORT} ${COM_SPEED_SERIAL}" || exit 0)
    set(TERMINAL "${Python2_EXECUTABLE}" -m serial.tools.miniterm ${COM_PORT} ${COM_SPEED_SERIAL})
endif()

################################################################################
# SPI flash settings (used by image generation (esptool[2]) and flash operations)
set(SPI_SPEED 40 CACHE STRING "SPI flash speed in MHz (default = 40MHz)")
set_property(CACHE SPI_SPEED PROPERTY STRINGS 20 26 40 80)
set(SPI_MODE qio CACHE STRING "SPI interface mode (consult your board's manual)")
set_property(CACHE SPI_MODE PROPERTY STRINGS qio qout dio dout)
set(SPI_SIZE 1M CACHE STRING "SPI flash size (byte size)")
set_property(CACHE SPI_SIZE PROPERTY STRINGS 256K 512K 1M 2M 4M)

set(flashimageoptions)
set(ESPTOOL2_BOOT_ARGS -quiet -bin -boot0) # Note: actually, there is no need for the flash size/mode args to esptool2, since the relevant bits are replaced by esptool.py during flash anyway
if(SPI_SPEED EQUAL 26)
    list(APPEND flashimageoptions -ff 26m)
    list(APPEND ESPTOOL2_BOOT_ARGS -26.7)
elseif(SPI_SPEED EQUAL 20)
    list(APPEND flashimageoptions -ff 20m)
    list(APPEND ESPTOOL2_BOOT_ARGS -20)
elseif(SPI_SPEED EQUAL 80)
    list(APPEND flashimageoptions -ff 80m)
    list(APPEND ESPTOOL2_BOOT_ARGS -80)
elseif(SPI_SPEED EQUAL 40)
    list(APPEND flashimageoptions -ff 40m)
    list(APPEND ESPTOOL2_BOOT_ARGS -40)
else()
    MESSAGE(FATAL_ERROR "Invalid option '${SPI_SPEED}' for variable SPI_SPEED")
endif()

if(SPI_MODE STREQUAL qout)
    list(APPEND flashimageoptions -fm qout)
    list(APPEND ESPTOOL2_BOOT_ARGS -qout)
elseif(SPI_MODE STREQUAL dio)
    list(APPEND flashimageoptions -fm dio)
    list(APPEND ESPTOOL2_BOOT_ARGS -dio)
elseif(SPI_MODE STREQUAL dout)
    list(APPEND flashimageoptions -fm dout)
    list(APPEND ESPTOOL2_BOOT_ARGS -dout)
elseif(SPI_MODE STREQUAL qio)
    list(APPEND flashimageoptions -fm qio)
    list(APPEND ESPTOOL2_BOOT_ARGS -qio)
else()
    MESSAGE(FATAL_ERROR "Invalid option '${SPI_MODE}' for variable SPI_MODE")
endif()

# For flash larger than 1024KB only one 1024KB block may be mapped to memory at the same time, i. e. a firmware image may never exceed 1024K
# The remaining flash area may be used to store a file system or additional firmware images (if the rboot bootloader is used)

if(SPI_SIZE STREQUAL 256K)
    list(APPEND flashimageoptions -fs 2m)
    list(APPEND ESPTOOL2_BOOT_ARGS -256)
    set(FLASH_SIZE 262144)
    set(SPIFF_SIZE_INIT 131072)
    set(INIT_BIN_ADDR 0x3c000)
    set(BLANK_BIN_ADDR 0x3e000)
elseif(SPI_SIZE STREQUAL 512K)
    list(APPEND flashimageoptions -fs 4m)
    list(APPEND ESPTOOL2_BOOT_ARGS -512)
    set(FLASH_SIZE 524288)
    set(SPIFF_SIZE_INIT 196608) #192K
    set(INIT_BIN_ADDR 0x7c000)
    set(BLANK_BIN_ADDR 0x7e000)
elseif(SPI_SIZE STREQUAL 1M)
    list(APPEND flashimageoptions -fs 8m)
    list(APPEND ESPTOOL2_BOOT_ARGS -1024)
    set(FLASH_SIZE 1048576)
    set(SPIFF_SIZE_INIT 524288)
    set(INIT_BIN_ADDR 0x0fc000)
    set(BLANK_BIN_ADDR 0x0fe000)
elseif(SPI_SIZE STREQUAL 2M)
    list(APPEND flashimageoptions -fs 16m)
    list(APPEND ESPTOOL2_BOOT_ARGS -2048)
    set(FLASH_SIZE 2097152)
    set(SPIFF_SIZE_INIT 524288)
    set(INIT_BIN_ADDR 0x1fc000)
    set(BLANK_BIN_ADDR 0x1fe000)
elseif(SPI_SIZE STREQUAL 4M)
    list(APPEND flashimageoptions -fs 32m)
    list(APPEND ESPTOOL2_BOOT_ARGS -4096)
    set(FLASH_SIZE 4194304)
    set(SPIFF_SIZE_INIT 524288)
    set(INIT_BIN_ADDR 0x3fc000)
    set(BLANK_BIN_ADDR 0x3fe000)
else()
    MESSAGE(FATAL_ERROR "Invalid option '${SPI_SIZE}' for variable SPI_SIZE")
endif()

if (SMING_ENABLE_SSL)
    # generate private key if not already there
    # TODO: figure out a platform-independent way. 
    # TODO2: generate into build directory and/or allow user to select directory via cache variable
    set(priv_key_dir "${CMAKE_SOURCE_DIR}/include/ssl")
    set(priv_key "${priv_key_dir}/private_key.h")
    if (NOT EXISTS "${priv_key}")
        if (NOT CMAKE_HOST_UNIX)
            message("WARNING: non-unix system detected. Private key generation uses a shell script. Make sure a suitable shell interpreter is available")
        endif()
        message("Generating unique certificate and key. This may take some time")
        
        file(MAKE_DIRECTORY "${priv_key_dir}")
        set(ENV{AXDIR} "${priv_key_dir}")
        execute_process(
            COMMAND "${SMING_HOME}/third-party/axtls-8266/tools/make_certs.sh"
            RESULT_VARIABLE make_certs_result
            ERROR_VARIABLE make_certs_error
        )
        if (NOT make_certs_result EQUAL 0)
            message(FATAL_ERROR "Certification generation failed:\n${make_certs_error}")
        endif()
    endif()
    set(SSL_KEY_INC_DIR "${CMAKE_SOURCE_DIR}/include")
endif()

# Add a convenience target to start the terminal
add_custom_target(terminal
    COMMENT "(Re-)start terminal"
    COMMAND ${KILL_TERM}
    COMMAND ${TERMINAL}
)

add_custom_target(flashinit
    COMMENT "Flash init data default and blank data."
    COMMAND ${ESPTOOL} -p ${COM_PORT} -b ${COM_SPEED_ESPTOOL} erase_flash
    COMMAND ${ESPTOOL} -p ${COM_PORT} -b ${COM_SPEED_ESPTOOL} write_flash ${flashimageoptions} 
        ${INIT_BIN_ADDR} "${SDK_BASE}/bin/esp_init_data_default.bin"
        ${BLANK_BIN_ADDR} "${SDK_BASE}/bin/blank.bin"
        # Note: in contrast to SMINGs original Makefiles, clearing the file system is omitted, 
        # since the whole flash has been erased and when flashing a new firmware that uses the system, it is overwritten anyway.
)

# Setup building instructions for a tool to run on the host computer during the build process
# An imported target 'name' is created for the resulting executable
function(_sming_build_tool name source_dir)
    include(ExternalProject)
    get_filename_component(host_exe_suffix "${CMAKE_COMMAND}" LAST_EXT)

    ExternalProject_Add(${name}-tool
        SOURCE_DIR "${source_dir}"
        EXCLUDE_FROM_ALL TRUE
        BUILD_ALWAYS TRUE
        STEP_TARGETS build
    )
    
    add_executable(${name} IMPORTED)
    ExternalProject_Get_property(${name}-tool BINARY_DIR)
    set_target_properties(${name} PROPERTIES IMPORTED_LOCATION "${BINARY_DIR}/${name}${host_exe_suffix}")
    add_dependencies(${name} ${name}-tool-build)
endfunction()

# Build the esptool2 utility for image firmware image generation
# TODO: replace by esptool (here and in rboot's CMakeLists.txt)
_sming_build_tool(esptool2 "${SMING_HOME}/../tools/esptool2")

################################################################################
# SPIFFY (file system) support
################################################################################
set(SPIFF_SIZE ${SPIFF_SIZE_INIT} CACHE STRING "Number of bytes reserved for the flash file system")

set(SPIFF_BIN_OUT "${CMAKE_CURRENT_BINARY_DIR}/spiff_rom.bin")
add_custom_target(spiff_rom) # proxy target for spiff_rom generation, does nothing until sming_spiff_files() is invoked

# The main project may invoke this function (once!) to add all files from the given directory to the flash file system.
# Calling this function automatically enables spiffy support for this project
function(SMING_SPIFF_FILES files_dir)
    if (TARGET spiff_rom_generate)
        message(FATAL_ERROR "Function sming_spiff_files(...) was already called. This function can only be used once")
    endif()
    
    # Note: The existence of the 'spiffy' target is used as an indicator that a file system image is available and should be included in flash commands
    _sming_build_tool(spiffy "${SMING_HOME}/../tools/spiffy")
        
    # create target for SPIFF rom generation
    if (IS_DIRECTORY "${files_dir}")
        add_custom_target(spiff_rom_generate ALL
            COMMAND spiffy ${SPIFF_SIZE} "${files_dir}" "${SPIFF_BIN_OUT}"
            COMMENT "Creating SPIFFS ROM from files in ${files_dir}"
        )
    else()
        add_custom_target(spiff_rom_generate ALL
            COMMAND spiffy ${SPIFF_SIZE} dummy.dir "${SPIFF_BIN_OUT}"
            COMMENT "Creating empty SPIFFS ROM"
        )
    endif()
    
    add_dependencies(spiff_rom spiff_rom_generate)
endfunction()

################################################################################
# Common helper functions for main build steps
################################################################################

# create an alias target for a custom target, if a target of the same name does not already exist
function(_SMING_CUSTOM_TARGET_ALIAS target alias)
    if (NOT TARGET ${alias})
        add_custom_target(${alias})
        add_dependencies(${alias} ${target})
    endif()
endfunction()

# Provide opportunity for linker script customization
# The template should allow cmake to configure the .irom0 section using 
# patterns @IROM0_ORG@ and @IROM0_SIZE@ for the section offset and size, respectively.
set(LINKER_SCRIPT_TEMPLATE "${SMING_HOME}/compiler/ld/rom.ld.in" CACHE FILEPATH "Path to linker script template")    
mark_as_advanced(LINKER_SCRIPT_TEMPLATE)

# generate a linker script with the given offset for the .irom0 section
function(_SMING_MAKE_LINKER_SCRIPT output irom_offset)
    MATH(EXPR IROM0_ORG "0x40200000 + ${irom_offset}" OUTPUT_FORMAT HEXADECIMAL)
    set(IROM0_SIZE "1M - ${irom_offset}")
    configure_file("${LINKER_SCRIPT_TEMPLATE}" "${output}" @ONLY)
endfunction()

# Create library target from the given application source files, which links to the sming framework.
# This library target is created as the main target by the sming_..._image() functions.
function(_SMING_MAKE_APP_LIB lib_target)
    
    add_library(${lib_target} STATIC ${ARGN})

    set_target_properties(${lib_target} PROPERTIES
        ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/${lib_target}"
        ARCHIVE_OUTPUT_NAME "app" # need fixed name, since it is hardcoded in linker script
    )
    sming_apply_debug_settings(${lib_target})
    target_link_libraries(${lib_target} PUBLIC sming) # this is the main framework target which propagates all necessary dependencies and compile options
    target_compile_definitions(${lib_target} PUBLIC
        SPIFF_SIZE=${SPIFF_SIZE}
    )
    target_include_directories(${lib_target} PRIVATE ${SSL_KEY_INC_DIR})
endfunction()

# Produce an empty source file for executable targets, since cmake's add_executable(...) requires at least one source file
set(DUMMY_C "${CMAKE_CURRENT_BINARY_DIR}/dummy.c")
file(GENERATE OUTPUT "${DUMMY_C}" CONTENT "")

# Create an executable target from a given library an linker script
function(_SMING_LINK_EXECUTABLE main_target exe_target linker_script)
    add_executable(${exe_target} "${DUMMY_C}")    
    target_link_libraries(${exe_target} ${main_target}) 
    target_link_options(${exe_target} PRIVATE 
        "SHELL:-u _Z4initv" # _Z4initv is 'void init()' as mangled C++ name: assume undefined from the beginning to avoid circular dependency user program <-> sming
        "SHELL:-u call_user_start"
        "SHELL:-u custom_crash_callback"
        "SHELL:-u Cache_Read_Enable_New" # allow rboot appcode to replace flash mapping code from SDK (required for rboot "Big flash mode")
        "SHELL:-u spiffs_get_storage_config" # from appspecific/rboot/overrides.c
        "-L${SDK_BASE}/ld" # for rom addresses
        "-L${SMING_HOME}/compiler/ld" # for common fragment included by main linker script
        "-T${linker_script}"
        "-Wl,-Map=$<TARGET_FILE:${exe_target}>.map"
    )
    # add dependency on linker script (sadly, there is no automatic dependency tracking for linker scripts => included fragments must be listed to trigger automatic recompilation on change)
    set_target_properties(${exe_target} PROPERTIES LINK_DEPENDS "${linker_script};${SMING_HOME}/compiler/ld/common_cmake.ld")
endfunction()

# Append custom command to print memory usage of exe_target
function(_SMING_SHOW_MEM_USAGE exe_target)
    add_custom_command(TARGET ${exe_target} POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E echo "Memory / Section info:"
        COMMAND "${CMAKE_COMMAND}" -E echo "------------------------------------------------------------------------------"
        COMMAND "${Python2_EXECUTABLE}" "${SMING_HOME}/../tools/memanalyzer.py" "${CMAKE_OBJDUMP}" "$<TARGET_FILE:${exe_target}>"
        COMMAND "${CMAKE_COMMAND}" -E echo "------------------------------------------------------------------------------"
    )
endfunction()

################################################################################
# Create a stand-alone firmware image (v1.0 type image)
################################################################################

function(SMING_STANDALONE_IMAGE main_target)    
    # replacement variables for configured scripts
    set(LINKER_SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/${main_target}.ld") # linker script for final executable, generated from LINKER_SCRIPT_TEMPLATE during build
    set(FLASH_SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/${main_target}_flash.cmake") # final flash script (created from template)

    set(IMAGE_BOOT "${CMAKE_CURRENT_BINARY_DIR}/${main_target}-boot.bin") # image started by ROM boot loader (contains all sections that need to be copied to RAM)
    set(IMAGE_BOOT_TEMP "${CMAKE_CURRENT_BINARY_DIR}/${main_target}-temp.bin") # temporary boot image to determine offset of .irom0 section
    set(IMAGE_IROM "${CMAKE_CURRENT_BINARY_DIR}/${main_target}-irom.bin") # image with code executed directly from IROM0
    set(IMAGE_IROM_OFFSET "@IMAGE_IROM_OFFSET@") # unknown at configuration time (keep replacement pattern in configured files)    

    # initial flash script configuration (final configuration is performed during build)
    configure_file("${SMING_HOME}/standalone_flash.cmake.in" "${FLASH_SCRIPT}.in" @ONLY)    
    # configure script for linker/flash script generation
    set(script_generator_script "${CMAKE_CURRENT_BINARY_DIR}/${main_target}_genscripts.cmake")
    configure_file("${SMING_HOME}/gen_scripts.cmake.in" "${script_generator_script}" @ONLY)

    # list of sections to include in the 'boot' image of a standalone rom
    set(ESPTOOL2_BOOT_SECTIONS .text .data .rodata)

    # MAIN TARGET: Library from application code 
    _sming_make_app_lib(${main_target} ${ARGN})

    # 1st link: create temporary executable to determine size of boot section (with a default offset for the irom section)
    set(temp_target ${main_target}-temp)
    set(linker_script_temp "${CMAKE_CURRENT_BINARY_DIR}/${temp_target}.ld")
    _sming_make_linker_script("${linker_script_temp}" "0xa000")
    _sming_link_executable(${main_target} ${temp_target} "${linker_script_temp}")
    
    # extract the boot image from temporary executable (its size is required to generate the final linker script)
    add_custom_command(OUTPUT "${IMAGE_BOOT_TEMP}"
        DEPENDS "$<TARGET_FILE:${temp_target}>"
        COMMENT "Extract boot image from temporary executable"
        COMMAND esptool2 ${ESPTOOL2_BOOT_ARGS} "$<TARGET_FILE:${temp_target}>" "${IMAGE_BOOT_TEMP}" ${ESPTOOL2_BOOT_SECTIONS}
    )
    
    # custom command/target to run linker/flash script generator
    add_custom_command(OUTPUT "${LINKER_SCRIPT}" "${FLASH_SCRIPT}"
        DEPENDS "${IMAGE_BOOT_TEMP}" "${FLASH_SCRIPT}.in"
        COMMENT "Generate linker script and flash scripts"
        COMMAND "${CMAKE_COMMAND}" -P "${script_generator_script}"
    )
    add_custom_target(${main_target}-scripts DEPENDS "${LINKER_SCRIPT}" "${FLASH_SCRIPT}")
    
    # 2nd link: create final executable based on correct irom section offset
    set(rom_target ${main_target}-rom)
    _sming_link_executable(${main_target} ${rom_target} "${LINKER_SCRIPT}")
    _sming_show_mem_usage(${rom_target})
    # additional target-level dependency to trigger linker script generation (unfortunately, cmake does not handle this automatically based on LINK_DEPENDS)
    add_dependencies(${rom_target} ${main_target}-scripts)

    # generate flash images from main executable
    add_custom_command(OUTPUT "${IMAGE_BOOT}" "${IMAGE_IROM}"
        DEPENDS "$<TARGET_FILE:${rom_target}>"
        COMMENT "Generate flash images"
        COMMAND esptool2 ${ESPTOOL2_BOOT_ARGS} "$<TARGET_FILE:${rom_target}>" "${IMAGE_BOOT}" ${ESPTOOL2_BOOT_SECTIONS}
        COMMAND esptool2 -quiet -lib "$<TARGET_FILE:${rom_target}>" "${IMAGE_IROM}"
    )
    add_custom_target(${main_target}-bin ALL DEPENDS "${IMAGE_BOOT}" "${IMAGE_IROM}") # ensure that all ROMs are always built
    
    # add flash/prog target via generated flash script
    add_custom_target(prog-${main_target}
        DEPENDS "${IMAGE_BOOT}" "${IMAGE_IROM}" "${FLASH_SCRIPT}"
        COMMENT "Flashing ${main_target} boot+irom0 images..."
        COMMAND ${KILL_TERM}
        COMMAND "${CMAKE_COMMAND}" -P "${FLASH_SCRIPT}"
        COMMAND ${TERMINAL}
    )
    _sming_custom_target_alias(prog-${main_target} prog)
        
    # without SPIFF, this is just an alias for prog
    set(comment_file_system)
    if(TARGET spiffy)
        set(comment_file_system " + file system")
    endif()
    add_custom_target(flash-${main_target}
        DEPENDS "${IMAGE_BOOT}" "${IMAGE_IROM}" "${FLASH_SCRIPT}" # SPIFF rom generation is handled via target-level dependency
        COMMENT "Flashing ${main_target} boot+irom0 images${comment_file_system}..."
        COMMAND ${KILL_TERM}
        COMMAND "${CMAKE_COMMAND}" -D "SPIFF_ROM=$<$<TARGET_EXISTS:spiffy>:${SPIFF_BIN_OUT}>" -P "${FLASH_SCRIPT}"
        COMMAND ${TERMINAL}
    )
    add_dependencies(flash-${main_target} spiff_rom) # need a target (which is always considered out of date) to enforce spiff_rom regeneration
    _sming_custom_target_alias(flash-${main_target} flash)
    
endfunction()

################################################################################
# Helper functions for rboot images
################################################################################

# Use _sming_make_app_lib() to create a library target from the given source files
# and augment it to be compatible with rboot
function(_SMING_MAKE_RBOOT_APP_LIB lib_target)
    _sming_make_app_lib(${lib_target} ${ARGN})
    target_sources(${lib_target} PRIVATE "${SMING_HOME}/appspecific/rboot/overrides.c") # spiffs_get_storage_config() for out-of-the-box spiffs loading with rboot

    target_compile_definitions(${lib_target} PUBLIC
        RBOOT_SPIFFS_0=${RBOOT_SPIFFS_0}
        RBOOT_SPIFFS_1=${RBOOT_SPIFFS_1}
    )
    
    target_link_libraries(${lib_target} PUBLIC rboot-appcode)
endfunction()

# Generate an rboot-compatible image from a library target containing the application code
function(_SMING_MAKE_RBOOT_ROM main_target rom_target rom_image rom_address)
    # create linker script
    set(linker_script "${CMAKE_CURRENT_BINARY_DIR}/${rom_target}.ld")
    math(EXPR link_offset "0x10 + (${rom_address} % 0x100000)" OUTPUT_FORMAT HEXADECIMAL) # 0x10 is v1.2 image header offset
    _sming_make_linker_script("${linker_script}" ${link_offset})
    
    # link executable
    _sming_link_executable(${main_target} ${rom_target} ${linker_script})    
    
    # generate flash images
    get_filename_component(rom_name "${rom_image}" NAME_WE)
    add_custom_command(OUTPUT "${rom_image}"
        DEPENDS "$<TARGET_FILE:${rom_target}>"
        COMMENT "Generate rboot image ${rom_name}"
        # Note: esptool2 does not require any flash size/config arguments, because flash setup is handled by the bootloader
        COMMAND esptool2 -quiet -bin -boot2  "$<TARGET_FILE:${rom_target}>" "${rom_image}" .text .data .rodata
    )
    add_custom_target(${rom_target}-bin ALL DEPENDS "${image_file}") # ensure that all ROMs are always built
endfunction()

# Generate target to write rboot + given ROM image + optional file system to flash
function(_SMING_MAKE_RBOOT_FLASH_TARGET main_target rom_image rom_address)    
    get_filename_component(rom_name "${rom_image}" NAME_WE)
    
    set(comment_file_system)
    if(TARGET spiffy)
        set(comment_file_system " + file system")
    endif()
    
    add_custom_target(flash-${main_target}
        DEPENDS "${rom_image}" "$<$<TARGET_EXISTS:spiffy>:${SPIFF_BIN_OUT}>"
        COMMENT "Flashing rboot + ${rom_name}${comment_file_system}..."
        COMMAND ${KILL_TERM}
        COMMAND "${ESPTOOL}" -p ${COM_PORT} -b ${COM_SPEED_ESPTOOL} write_flash ${flashimageoptions} 
            0x00000 "$<TARGET_PROPERTY:rboot,IMAGE_FILE>" # rboot image (bootloader)
            0x01000 "${SDK_BASE}/bin/blank.bin" # rboot config (initialized on first boot)
            ${rom_address} "${rom_image}" # application image (rom0)
            $<$<TARGET_EXISTS:spiffy>:${RBOOT_SPIFFS_0}> "$<$<TARGET_EXISTS:spiffy>:${SPIFF_BIN_OUT}>" # file system, if enabled
        COMMAND ${TERMINAL}
    )
    add_dependencies(flash-${main_target} rboot spiff_rom) # need a target (which is always considered out of date) to enforce spiff_rom regeneration
    _sming_custom_target_alias(flash-${main_target} flash)
    
    add_custom_target(prog-${main_target}
        DEPENDS "${rom_image}"
        COMMENT "Flashing rboot + ${rom_name}..."
        COMMAND ${KILL_TERM}
        COMMAND "${ESPTOOL}" -p ${COM_PORT} -b ${COM_SPEED_ESPTOOL} write_flash ${flashimageoptions} 
            0x00000 "$<TARGET_PROPERTY:rboot,IMAGE_FILE>" # rboot image (bootloader)
            0x01000 "${SDK_BASE}/bin/blank.bin" # rboot config (initialized on first boot)
            ${rom_address} "${rom_image}" # application image (rom0)
        COMMAND ${TERMINAL}
    )
    add_dependencies(prog-${main_target} rboot) # need a target (which is always considered out of date) to enforce spiff_rom regeneration
    _sming_custom_target_alias(prog-${main_target} prog)
endfunction()

################################################################################
# Functions to create firmware images for use with the rboot bootloader
################################################################################

# Use this function if you want to build RBOOT, but no particular image
# This function is automatically invoked when building an rboot image, so there is no need 
# to call it explicitly when using sming_rboot_[gpio_]image()
function(SMING_ENABLE_RBOOT)
    if (NOT TARGET rboot)
        # Note: rboot uses esptool2 (does not need flash options)
        add_subdirectory("${SMING_HOME}/third-party/rboot" rboot)

        # add config option where to place spiffs (we reuse 'RBOOT_' namespace here for convenience, but rboot knows nothing abouth spiffs so - technically - this is not an RBOOT option)
        set(RBOOT_SPIFFS_0 0x100000 CACHE STRING "ROM address of spiffs (file system) when using rboot.")
        set(RBOOT_SPIFFS_1 0x300000 CACHE STRING "[UNUSED] fallback ROM address of spiffs (file system) when RBOOT_SPIFFS_0 is empty.")

        # convenience command to flash the bootloader only
        add_custom_target(flash-rboot
            COMMAND ${KILL_TERM}
            COMMAND "${ESPTOOL}" -p ${COM_PORT} -b ${COM_SPEED_ESPTOOL} write_flash ${flashimageoptions} 
                0x00000 "$<TARGET_PROPERTY:rboot,IMAGE_FILE>"
                0x01000 "${SDK_BASE}/bin/blank.bin"
                # ${RBOOT_ROM_OFFSET} "${SDK_BASE}/bin/blank.bin" # kill first image
        )
        add_dependencies(flash-rboot rboot)
    endif()
endfunction()

# This function creates firmware images for use with the rboot bootloader.
# The number of images is determined automatically depending on flash size and rboot configuration.
# For flash sizes >= 2MB a single image is usually sufficient, because every the ESP8266 can map only 1MB at a time into its address space.
# For smaller flashes, two images linked to different flash offsets (within the 1MB range) are created.
function(SMING_RBOOT_IMAGE main_target)
    # pull in rboot and its configuration variables
    sming_enable_rboot()
            
    # Create library from application code
    _sming_make_rboot_app_lib(${main_target} ${ARGN})
    
    # create first image
    set(rom0_target ${main_target}-rom0)
    set(rom0_address ${RBOOT_ROM_OFFSET})
    math(EXPR rom0_address "${rom0_address} % 0x100000" OUTPUT_FORMAT HEXADECIMAL)
    _sming_make_rboot_rom(${main_target} ${rom0_target} "${CMAKE_CURRENT_BINARY_DIR}/${rom0_target}.bin" ${rom0_address})
    _sming_show_mem_usage(${rom0_target}) # print only for rom0, since memory usage should be the same for both roms
    
    # if necessary, create second image
    set(rom1_address ${RBOOT_CUSTOM_ROM1_ADDR})
    if ("${rom1_address}" STREQUAL "") # if second ROM address is not given, determine it from flash size
        math(EXPR rom1_address "${FLASH_SIZE} / 2 + ${RBOOT_ROM_OFFSET}" OUTPUT_FORMAT HEXADECIMAL)
    endif()
    math(EXPR rom1_address "${rom1_address} % 0x100000" OUTPUT_FORMAT HEXADECIMAL)
    
    if (NOT "${rom0_address}" STREQUAL "${rom1_address}")     
        # add define for OTA code (not used anywhere else in SMING or rBoot
        target_compile_definitions(${main_target} PUBLIC RBOOT_TWO_ROMS)
        
        set(rom1_target ${main_target}-rom1)
        _sming_make_rboot_rom(${main_target} ${rom1_target} "${CMAKE_CURRENT_BINARY_DIR}/${rom1_target}.bin" ${rom1_address})
    endif()
    
    # generate target to write rboot + first ROM and optionally spiffs to flash
    _sming_make_rboot_flash_target(${main_target} "${CMAKE_CURRENT_BINARY_DIR}/${rom0_target}.bin" ${RBOOT_ROM_OFFSET})

endfunction()

# Create an rboot image for GPIO booting (e. g. a fallback image to run when a special button is pressed at boot time)
function(SMING_RBOOT_GPIO_IMAGE main_target)
    sming_enable_rboot()
    if (NOT "${RBOOT_GPIO_MODE}" STREQUAL "fixed")
        message(FATAL_ERROR "Set RBOOT_GPIO_MODE to 'fixed' to enable rboot gpio image generation.")
    endif()
    
    # Create  library from application code
    _sming_make_rboot_app_lib(${main_target} ${ARGN})

    # create rboot ROM
    set(rom_image "${CMAKE_CURRENT_BINARY_DIR}/${main_target}.bin")
    _sming_make_rboot_rom(${main_target} ${main_target}-rom "${rom_image}" ${RBOOT_GPIO_ROM_ADDR})
    _sming_show_mem_usage(${main_target}-rom)
    
    # generate target to write rboot + ROM and optionally spiffs to flash
    _sming_make_rboot_flash_target(${main_target} "${rom_image}" ${RBOOT_GPIO_ROM_ADDR})
endfunction()
