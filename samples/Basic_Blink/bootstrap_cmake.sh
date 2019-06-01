#!/bin/bash

echo "Prepare build directory";
build_dir=$(pwd)/build-cmake 
mkdir -p $build_dir || { echo "Could not create build directory"; exit 1; }
cd $build_dir || { echo "Could not change to build directory"; exit 1; }

# Copy Sming/toolchain.cmake to root directory of your SDK, then adapt next line accordingly
toolchain_file=/path/to/sdk/root/directory/toolchain.cmake

echo "Running cmake..."
if cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE="$toolchain_file" -G"Unix Makefiles" -DSMING_ENABLE_SSL=ON -DCOM_SPEED_ESPTOOL=1000000 .. ; then
    echo run 'make' to build Sming and project. cmake will re-run automatically, if needed
    $SHELL
fi
