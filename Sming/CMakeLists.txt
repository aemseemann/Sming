cmake_minimum_required(VERSION 3.9)

# enforce c++11
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

project(sming LANGUAGES C CXX ASM)

set(SMING_HOME ${CMAKE_CURRENT_SOURCE_DIR})
set(SMING_HOME ${SMING_HOME} PARENT_SCOPE) # may be useful in parent scope

set(THIRD_PARTY_DIR ${SMING_HOME}/third-party)

# also used by sming.cmake for terminal setup
set(COM_SPEED_SERIAL 115200 CACHE STRING "Baud rate for serial connection (Note: Boards with 26MHz crystal will boot at 74880, i. e. set your terminal to this rate to receive messages from the ROM boot loader.")

set(SMING_DEBUG_PRINT_FILENAME_AND_LINE OFF CACHE BOOL "By default `debugf` does not print file name and line number.")
set(SMING_DEBUG_VERBOSE_LEVEL 2 CACHE STRING "Defaut debug verbose level is INFO, where DEBUG=3 INFO=2 WARNING=1 ERROR=0")
set(SMING_ENABLE_CMD_EXECUTOR ON CACHE BOOL "Disable CommandExecutor functionality if not used and save some ROM and RAM")

set(SMING_ENABLE_SSL ON CACHE BOOL "Enable SSL functionality")
set(SMING_ENABLE_CUSTOM_LWIP lwip CACHE STRING "select 'builtin' to use binary lwip from SDK, 'lwip' (default) or 'lwip2' (does not support espconn) to compile open source version from esp_open")
set_property(CACHE SMING_ENABLE_CUSTOM_LWIP PROPERTY STRINGS builtin lwip lwip2)

set(SMING_ENABLE_ESPCONN OFF CACHE BOOL "Enable espconn API for open-source lwip")
set(SMING_ENABLE_LWIPDEBUG OFF CACHE BOOL "compile open-source lwip with debugging enabled")

set(SMING_ENABLE_WPS OFF CACHE BOOL "enable WPS functionality (experimental?)")

set(SMING_ENABLE_GDB OFF CACHE BOOL "Enable Espressif gdbstubs")
set(SMING_ENABLE_CUSTOM_HEAP OFF CACHE BOOL "Enable custom memory allocator")
set(SMING_ENABLE_CUSTOM_PWM ON CACHE BOOL "Select custom PWM library implementation")

# TODO: Set automatically for RELEASE builds (use RELWITHDEBINFO for basic gdbstubs)
set(SMING_RELEASE OFF CACHE BOOL "Disable debug functionality (do not add basic gdbstubs)")

set(SDK_BASE "" CACHE PATH "Path to sdk base folder (e. g. path/to/esp-open-sdk/sdk). If empty, the internal SDK that comes with sming is used instead.")

# Fetch git submodules that are not already present and apply patches
find_package(Git)
if(NOT Git_FOUND)
    message(FATAL_ERROR "Git not found: Cannot check out submodules")
endif()

# run git command in the given working directory and write command output to a variable named 'git_output'
function(GIT_RUN_IN working_directory)
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" ${ARGN}
        WORKING_DIRECTORY "${working_directory}"
        RESULT_VARIABLE git_ok
        OUTPUT_VARIABLE git_output
        ERROR_VARIABLE git_error
    )
    if (NOT git_ok EQUAL 0)
        message(FATAL_ERROR "Git command failed:\n${git_error}")
    endif()
    set(git_output "${git_output}" PARENT_SCOPE)
endfunction()

# init/checkout a submodule and optionally apply a patch file from ${path}/../.patches matching the name of the submodule
# Arguments:
# - path: absolute path to submodule
# - file_to_check: path to a file (relative to submodule, i. e. ${path}) that will be present in the submodule if it has been prepared already and should not be modified
function(PREPARE_SUBMODULE path file_to_check)
    if (EXISTS "${path}/${file_to_check}")
        return()
    endif()    
    get_filename_component("${path}" module_name NAME)
    get_filename_component("${path}" basedir DIRECTORY)
    message("Preparing submodule ${path}...")
    git_run_in("${SMING_HOME}" submodule update --init --recursive "${path}")    
    set(patch_file "${basedir}/.patches/${module_name}.patch")
    if (EXISTS "${patch_file}")
        git_run_in("${path}" apply -v "${patch_file}" --ignore-whitespace --whitespace=nowarn)
    endif()
endfunction()

# Prepare Arduino libraries embedded as submodules
git_run_in("${SMING_HOME}" submodule status Libraries)
string(REPLACE ";" "\\\\;" git_output "${git_output}") # split lines
string(REPLACE "\n" ";" git_output "${git_output}")
foreach(line IN LISTS git_output)
    string(STRIP "${line}" line)
    if (NOT line STREQUAL "")
        string(REGEX MATCH "Libraries[^ \t]+" lib "${line}")
        prepare_submodule("${SMING_HOME}/${lib}" "library.properties")
    endif()
endforeach()

prepare_submodule("${THIRD_PARTY_DIR}/rboot" "Makefile")
prepare_submodule("${THIRD_PARTY_DIR}/spiffs" "makefile")
prepare_submodule("${THIRD_PARTY_DIR}/http-parser" "Makefile")
prepare_submodule("${THIRD_PARTY_DIR}/ws_parser" "Makefile")

# Prepare build instructions
set(EXTRA_DEFINES)
set(EXTRA_INCDIR)

if ("${SDK_BASE}" STREQUAL "")
    prepare_submodule("${THIRD_PARTY_DIR}/ESP8266_NONOS_SDK" "Makefile")
    set(SDK_BASE "${THIRD_PARTY_DIR}/ESP8266_NONOS_SDK")
    list(APPEND EXTRA_DEFINES "SDK_INTERNAL")
endif()

# collect all subdirectories in "services"

file(GLOB service_dirs_glob_result LIST_DIRECTORIES true RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" "Services/*")
set(SERVICE_DIRS)
foreach(entry IN ITEMS ${service_dirs_glob_result})
    if (IS_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/${entry}")
        list(APPEND SERVICE_DIRS ${entry})
    endif()
endforeach()

# collect available Arduino libraries
file(GLOB library_dirs_glob_result LIST_DIRECTORIES true RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" "Libraries/*" "Libraries/*/src")
set(LIBRARY_DIRS)
foreach(entry IN ITEMS ${library_dirs_glob_result})
    if (IS_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/${entry}")
        list(APPEND LIBRARY_DIRS ${entry})
    endif()
endforeach()

# TODO: make sure all required 3rd party submodules are in place (git submodule init + patch)
# (Note: it is not necessary to 're-fetch' at some place, because if the user really changes stuff in the submodules, he is most likely doing it on purpose and does not want the build system to interfere)
# (The only case to consider is if the main repo has been updated and a submodule pointer is not up to date anymore... Not sure how to distinguish this from an active modification by the user)

# Collect sources by file globbing for now (maybe conversion to explicit lists is the better way to go)
set(MODULES
    "system"
    "system/helpers"
    "Wiring"
    "appinit"
    "SmingCore"
    "SmingCore/Data"
    "SmingCore/Data/Stream"
    "SmingCore/Network"
    "SmingCore/Network/Http"
    "SmingCore/Network/Http/Websocket"
    "SmingCore/Platform"
    ${SERVICE_DIRS}
    ${LIBRARY_DIRS} # TODO: compile each library directory as separate library that has a dependency on sming -> user has to link to them explicitly
    "${THIRD_PARTY_DIR}/spiffs/src"
    "${THIRD_PARTY_DIR}/http-parser"
    "${THIRD_PARTY_DIR}/ws_parser"
)

if (SMING_ENABLE_SSL)
    #add axtls support modules
    list(APPEND MODULES
        "${THIRD_PARTY_DIR}/axtls-8266/compat"
        "${THIRD_PARTY_DIR}/axtls-8266/replacements"
    )
endif()

# Apply debug settings to every source file. Unfortunately, there is no generator expression to reference the current source file :(
function(SMING_APPLY_DEBUG_SETTINGS target)
    get_target_property(tgt_sources ${target} SOURCES)
    foreach(src IN LISTS tgt_sources)
        get_filename_component(basename "${src}" NAME_WE)
        set_property(SOURCE "${src}" APPEND PROPERTY COMPILE_DEFINITIONS "DEBUG_VERBOSE_LEVEL=${SMING_DEBUG_VERBOSE_LEVEL}" "CUST_FILE_BASE=${basename}" "DEBUG_PRINT_FILENAME_AND_LINE=$<BOOL:${SMING_DEBUG_PRINT_FILENAME_AND_LINE}>")
    endforeach()
endfunction()

# => esp-gdbstub
if(SMING_ENABLE_GDB)
    prepare_submodule("${THIRD_PARTY_DIR}/esp-gdbstub" "Makefile")
    list(APPEND MODULES "${THIRD_PARTY_DIR}/esp-gdbstub")
    list(APPEND EXTRA_INCDIR "${THIRD_PARTY_DIR}/esp-gdbstub")
elseif(NOT SMING_RELEASE)
    list(APPEND MODULES gdb)
endif()

# tweaked libmain from SDK
set(LIBMAIN "${CMAKE_CURRENT_BINARY_DIR}/libmain.a")
add_custom_command(
    OUTPUT "${LIBMAIN}"
    COMMAND "${CMAKE_OBJCOPY}" -W Cache_Read_Enable_New "${SDK_BASE}/lib/libmain.a" "${LIBMAIN}"
    COMMENT "Prepare libmain for use with RBOOT" # weaken symbol that may be overridden by rboot app code
)
add_custom_target(mod_libmain DEPENDS "${LIBMAIN}")
add_library(main STATIC IMPORTED GLOBAL)
add_dependencies(main mod_libmain)
set_property(TARGET main PROPERTY IMPORTED_LOCATION "${LIBMAIN}")

if(SMING_ENABLE_CUSTOM_HEAP)
    # => umm_malloc (custom heap allocation)
    list(APPEND THIRD_PARTY_DATA "${THIRD_PARTY_DIR}/umm_malloc/Makefile")
    list(APPEND MODULES custom_heap "${THIRD_PARTY_DIR}/umm_malloc/src")
    list(APPEND EXTRA_INCDIR
        "${THIRD_PARTY_DIR}/umm_malloc/src" 
        "${THIRD_PARTY_DIR}/umm_malloc/includes/c-helper-macros"
    )
    add_custom_command(TARGET mod_libmain POST_BUILD
        COMMAND "${CMAKE_AR}" -d "${LIBMAIN}" mem_manager.o
        COMMENT "Remove default allocator from libmain"
    )
endif()

if (SMING_ENABLE_CUSTOM_PWM)
    prepare_submodule("${THIRD_PARTY_DIR}/pwm" "pwm.c")
    add_library(pwm STATIC "${THIRD_PARTY_DIR}/pwm/pwm.c")
    target_compile_options(pwm PRIVATE -mtext-section-literals -finline-functions)
    target_compile_definitions(pwm PRIVATE SDK_PWM_PERIOD_COMPAT_MODE=1)
    # TODO: figure out common set of includes to re-use for every sub-library
    target_include_directories(pwm PRIVATE 
        "${SDK_BASE}/include"
        "${CMAKE_CURRENT_SOURCE_DIR}/include" # for user_config.h
        "${CMAKE_CURRENT_SOURCE_DIR}/system/include"
        "${CMAKE_CURRENT_SOURCE_DIR}/Wiring"
    )
    sming_apply_debug_settings(pwm)
else()
    add_library(pwm STATIC IMPORTED GLOBAL)
    set_property(TARGET pwm PROPERTY IMPORTED_LOCATION "${SDK_BASE}/lib/libpwm.a")
endif()

if(SMING_ENABLE_CUSTOM_LWIP STREQUAL builtin)
    add_library(lwip STATIC IMPORTED GLOBAL)
    set_target_properties(lwip PROPERTIES
        IMPORTED_LOCATION "${SDK_BASE}/lib/liblwip.a"
        INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_SOURCE_DIR)/system/esp-lwip/"
    )
elseif(SMING_ENABLE_CUSTOM_LWIP STREQUAL lwip)
    prepare_submodule("${THIRD_PARTY_DIR}/esp-open-lwip" "Makefile.open")
    add_subdirectory("${THIRD_PARTY_DIR}/esp-open-lwip")
elseif(SMING_ENABLE_CUSTOM_LWIP STREQUAL lwip2)
    if (SMING_ENABLE_ESPCONN)
        message(FATAL_ERROR "LWIP2 does not support espconn_* functions. Make sure to set SMING_ENABLE_CUSTOM_LWIP to 'builtin' or 'lwip'.")
    endif()
    prepare_submodule("${THIRD_PARTY_DIR}/lwip2" "Makefile.sming")
    add_subdirectory("${THIRD_PARTY_DIR}/lwip2")
else()
    message(FATAL_ERROR "Invalid setting of ${SMING_ENABLE_CUSTOM_LWIP}")
endif()


set(SMING_SOURCES)
foreach(mod IN ITEMS ${MODULES})
    file(GLOB src LIST_DIRECTORIES false RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" "${mod}/*.c" "${mod}/*.cpp" "${mod}/*.h" "${mod}/*.s" "${mod}/*.S")
    list(APPEND SMING_SOURCES ${src})
endforeach()

add_library(sming ${SMING_SOURCES})
set_target_properties(sming PROPERTIES LINKER_LANGUAGE CXX)
target_compile_options(sming PRIVATE -Werror -mtext-section-literals -finline-functions) # disallow warnings

target_compile_definitions(sming PUBLIC
    "SMING_INCLUDED=1" # TODO: propagate from axtls instead
    "ESP8266=1"
    "ARDUINO=106" # needed for various Arduino libs
    "__ets__" # used by some 3rd party libs
    "COM_SPEED_SERIAL=${COM_SPEED_SERIAL}"
    "ENABLE_CMD_EXECUTOR=$<BOOL:${SMING_ENABLE_CMD_EXECUTOR}>"
    ${EXTRA_DEFINES}
)

target_include_directories(sming PUBLIC
    "${SDK_BASE}/include"
    "${SDK_BASE}/include/json"
    "${SMING_HOME}/include"
    "${LWIP_INCDIR}"
    "${SMING_HOME}/system/include"
    "${SMING_HOME}/Wiring"
    "${SMING_HOME}/Libraries"
    "${SMING_HOME}/SmingCore"
    "${SMING_HOME}/Services/SpifFS"
    "${THIRD_PARTY_DIR}/rboot"
    "${THIRD_PARTY_DIR}/rboot/appcode"
    "${THIRD_PARTY_DIR}/spiffs/src"
    "${THIRD_PARTY_DIR}/http-parser"
    "${THIRD_PARTY_DIR}/ws_parser"
    ${SERVICE_DIRS}
    ${LIBRARY_DIRS} # TODO: libraries use SMING functionality -> they have to depend on smingcore, but smingcore does not have to depend on libraries
)


# The PROGMEM_L32 seems to be used only by the http-parser: there is no need to add it to the public interface
if(MFORCE32) # determine in toolchain file
    # write this option to file, since it seems impossible to get this quoted right on the command line...
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/compile_definitions_progmen.h" "#define PROGMEM_L32 __attribute__((aligned(4))) __attribute__((section(\".irom.text\")))")
    target_compile_options(sming PRIVATE -mforce-l32 -include "${CMAKE_CURRENT_BINARY_DIR}/compile_definitions_progmen.h")
else()
    target_compile_definitions(sming PRIVATE -DPROGMEM_L32=)
endif()

# The Sming  Makefile simply adds every source directory to the include path. This seems kind of stupid, therefore we add only the directories absolutely necessary
target_include_directories(sming PRIVATE
    "${SMING_HOME}/SmingCore/Network"
    "${SMING_HOME}/SmingCore/Network/Http"
    "${SMING_HOME}/SmingCore/Platform"
    ${EXTRA_INCDIR}
)

# create import libs for precompiled SDK libs
set(SDK_BINARY_LIBS phy pp wpa net80211 crypto smartconfig)
foreach(lib IN ITEMS ${SDK_BINARY_LIBS})
    add_library(${lib} STATIC IMPORTED GLOBAL)
    set_property(TARGET ${lib} PROPERTY IMPORTED_LOCATION "${SDK_BASE}/lib/lib${lib}.a")
endforeach()
# circular dependencies between these two...
target_link_libraries(wpa INTERFACE net80211)
target_link_libraries(net80211 INTERFACE wpa)

target_link_libraries(sming PUBLIC 
    hal # somewhere in toolchain compiler search path
    main
    lwip
    pwm
    ${SDK_BINARY_LIBS}
    "${CMAKE_CURRENT_SOURCE_DIR}/compiler/lib/libmicroc.a"
    "${CMAKE_CURRENT_SOURCE_DIR}/compiler/lib/libmicrogcc.a"
)
# replace system_restart_local from libmain with SMING's version
target_link_options(sming INTERFACE -Wl,-wrap,system_restart_local "SHELL:-u __wrap_system_restart_local")

target_link_libraries(main INTERFACE sming) # circular dependency...

if (SMING_ENABLE_WPS)
    target_compile_definitions(sming PUBLIC ENABLE_WPS=1)
    target_link_libraries(sming INTERFACE "${SDK_BASE}/lib/libwps.a")
endif()

if (SMING_ENABLE_SSL)
    prepare_submodule("${THIRD_PARTY_DIR}/axtls-8266" "Makefile")
    add_subdirectory("${THIRD_PARTY_DIR}/axtls-8266")
    target_link_libraries(sming PUBLIC axtls)
    # hack: some files of axtls reference symbols from sming => we need a circular dependency here
    # TODO: figure out a better way
    cmake_policy(SET CMP0079 NEW)
    target_link_libraries(axtls INTERFACE sming)
endif()

sming_apply_debug_settings(sming)
