#!/usr/bin/env bash
set -euo pipefail

source_dir="$1"
destination="$2"
ndk="${ANDROID_HOME}/ndk/26.3.11579264"
sdk_manager="$(find "$ANDROID_HOME/cmdline-tools" -path '*/bin/sdkmanager' -type f | sort -V | tail -n 1)"
test -x "$sdk_manager"
"$sdk_manager" --install 'ndk;26.3.11579264' 'cmake;3.22.1'
cmake_bin="${ANDROID_HOME}/cmake/3.22.1/bin"
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT
"$cmake_bin/cmake" -S "$source_dir" -B "$build_dir" -G Ninja \
  -DCMAKE_MAKE_PROGRAM="$cmake_bin/ninja" \
  -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-26 -DANDROID_STL=c++_static \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_EXE_LINKER_FLAGS="-Wl,-z,max-page-size=16384" \
  -DBUILD_SHARED_LIBS=OFF -DSD_WEBP=OFF -DSD_WEBM=OFF -DSD_SERVER_BUILD_FRONTEND=OFF \
  -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF
"$cmake_bin/cmake" --build "$build_dir" --target sd-cli --parallel 2
binary="$(find "$build_dir" -type f -name sd-cli -print -quit)"
install -Dm755 "$binary" "$destination/libzaskia_flux.so"
