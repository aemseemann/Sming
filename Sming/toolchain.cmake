# toolchain file for xtensa toolchain (used for esp8266 device)

# !! Copy this file to the root directory of your SDK (tested with https://github.com/pfalcon/esp-open-sdk) !!
# The variable SDK_BASE will be set to the location of this file.
# Further paths are relative to ${SDK_BASE}

# We are cross compiling so we don't want compiler tests to run, as they will fail
set(CMAKE_SYSTEM_NAME Generic)
# Set processor type
set(CMAKE_SYSTEM_PROCESSOR l106)

set(CMAKE_CROSSCOMPILING 1)
set_property(GLOBAL PROPERTY TARGET_SUPPORTS_SHARED_LIBS FALSE)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

set(SDK_BASE "${CMAKE_CURRENT_LIST_DIR}")

set(tool_prefix "${SDK_BASE}/xtensa-lx106-elf/bin/xtensa-lx106-elf-")
set(CMAKE_C_COMPILER ${tool_prefix}gcc)
set(CMAKE_CXX_COMPILER ${tool_prefix}g++) 
# TODO: Only gcc or g++ is is needed, cmake can figure out the other one automatically.

set(CMAKE_C_FLAGS_INIT "-Wpointer-arith -Wundef -mlongcalls -nostdlib -Wl,-EL -fdata-sections -ffunction-sections -DICACHE_FLASH")
set(CMAKE_ASM_FLAGS_INIT "${CMAKE_C_FLAGS_INIT}")
set(CMAKE_CXX_FLAGS_INIT "${CMAKE_C_FLAGS_INIT} -fno-rtti -fno-exceptions -felide-constructors")
set(CMAKE_EXE_LINKER_FLAGS_INIT "-nostdlib -Wl,-static -Wl,--gc-sections")

# Note: we use 'Os' due to the space constraints, also O2 and other stuff may try to link to symbols not present in libmicroc. Adding -g may not be too useful, but does not harm either
set(CMAKE_C_FLAGS_RELEASE "-Os -g -DNDEBUG" CACHE STRING "" FORCE) # we have to enforce these flags, since otherwise, cmake automatically appends -O3 -DNDEBUG
set(CMAKE_ASM_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE}" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE}" CACHE STRING "" FORCE)

execute_process(COMMAND "${CMAKE_C_COMPILER}" --help=target OUTPUT_VARIABLE COMPILER_TARGET_HELP_OUT)
if (COMPILER_TARGET_HELP_OUT MATCHES "mforce-l32")
    set(MFORCE32 TRUE)
endif()
unset(COMPILER_TARGET_HELP_OUT)


