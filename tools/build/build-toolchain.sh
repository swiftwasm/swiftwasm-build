#!/bin/bash

set -ex
SOURCE_PATH="$(cd "$(dirname "$0")/../../.." && pwd)"
TOOLS_BUILD_PATH="$(cd "$(dirname "$0")" && pwd)"

BUILD_SDK_PATH="$SOURCE_PATH/build-sdk"
WASI_SYSROOT_PATH="$BUILD_SDK_PATH/wasi-sysroot"

case $(uname -s) in
  Darwin)
    HOST_PRESET=webassembly-host-install
    HOST_SUFFIX=macosx-$(uname -m)
  ;;
  Linux)
    HOST_PRESET=webassembly-linux-host-install
    HOST_SUFFIX=linux-$(uname -m)
  ;;
  *)
    echo "Unrecognised platform $(uname -s)"
    exit 1
  ;;
esac

OPTIONS_BUILD_HOST_TOOLCHAIN=1
OPTIONS_DAILY_SNAPSHOT=0

while [ $# -ne 0 ]; do
  case "$1" in
    --skip-build-host-toolchain)
    OPTIONS_BUILD_HOST_TOOLCHAIN=0
  ;;
  *)
    echo "Unrecognised argument \"$1\""
    exit 1
  ;;
  esac
  shift
done

PACKAGING_DIR="$SOURCE_PATH/build/Packaging"
HOST_TOOLCHAIN_DESTDIR=$PACKAGING_DIR/host-toolchain
TARGET_TOOLCHAIN_DESTDIR=$PACKAGING_DIR/target-toolchain

HOST_BUILD_ROOT=$SOURCE_PATH/build/WebAssemblyCompiler
TARGET_BUILD_ROOT=$SOURCE_PATH/build/WebAssembly
HOST_BUILD_DIR=$HOST_BUILD_ROOT/Ninja-ReleaseAssert

build_host_toolchain() {
  # Build the host toolchain and SDK first.
  env SWIFT_BUILD_ROOT="$HOST_BUILD_ROOT" \
    "$SOURCE_PATH/swift/utils/build-script" \
    --preset-file="$TOOLS_BUILD_PATH/build-presets.ini" \
    --preset=$HOST_PRESET \
    --build-dir="$HOST_BUILD_DIR" \
    HOST_ARCHITECTURE="$(uname -m)" \
    INSTALL_DESTDIR="$HOST_TOOLCHAIN_DESTDIR"
}

build_target_toolchain() {

  local COMPILER_RT_BUILD_DIR="$TARGET_BUILD_ROOT/compiler-rt-wasi-wasm32"
  cmake -B "$COMPILER_RT_BUILD_DIR" \
    -D CMAKE_TOOLCHAIN_FILE="$TOOLS_BUILD_PATH/compiler-rt-cache.cmake" \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_C_COMPILER="$HOST_BUILD_DIR/llvm-$HOST_SUFFIX/bin/clang" \
    -D CMAKE_CXX_COMPILER="$HOST_BUILD_DIR/llvm-$HOST_SUFFIX/bin/clang++" \
    -D CMAKE_RANLIB="$HOST_BUILD_DIR/llvm-$HOST_SUFFIX/bin/llvm-ranlib" \
    -D CMAKE_AR="$HOST_BUILD_DIR/llvm-$HOST_SUFFIX/bin/llvm-ar" \
    -D CMAKE_C_COMPILER_LAUNCHER="$(which sccache)" \
    -D CMAKE_CXX_COMPILER_LAUNCHER="$(which sccache)" \
    -D CMAKE_INSTALL_PREFIX="$TARGET_TOOLCHAIN_DESTDIR/usr/lib/clang/13.0.0/" \
    -D CMAKE_SYSROOT="${WASI_SYSROOT_PATH}" \
    -G Ninja \
    -S "$SOURCE_PATH/llvm-project/compiler-rt"

  ninja install -C "$COMPILER_RT_BUILD_DIR"

  # Only configure LLVM to use CMake functionalities in LLVM
  local LLVM_TARGET_BUILD_DIR="$TARGET_BUILD_ROOT/llvm-wasi-wasm32"
  cmake -B "$LLVM_TARGET_BUILD_DIR" \
    -D CMAKE_BUILD_TYPE=Release \
    -D LLVM_ENABLE_ZLIB=NO \
    -D LLVM_ENABLE_LIBXML2=NO \
    -G Ninja \
    -S "$SOURCE_PATH/llvm-project/llvm"

  local SWIFT_STDLIB_BUILD_DIR="$TARGET_BUILD_ROOT/swift-stdlib-wasi-wasm32"

  # FIXME(katei): Platform/WASI is not recognized as a platform in LLVM, so it reports
  # "Unable to determine platform" while handling LLVM options.
  # Set WASI as a UNIX platform to spoof LLVM
  # FIXME(katei): host-build clang's libcxx is capable with LLVM, but it somehow
  # fails libcxx version check. So activate LLVM_COMPILER_CHECKED to spoof the checker
  # SWIFT_DRIVER_TEST_OPTIONS is used to specify clang resource dir for wasm32-unknown-wasi
  # because it's not built beside clang
  cmake -B "$SWIFT_STDLIB_BUILD_DIR" \
    -C "$SOURCE_PATH/swift/cmake/caches/Runtime-WASI-wasm32.cmake" \
    -D CMAKE_TOOLCHAIN_FILE="$TOOLS_BUILD_PATH/toolchain-wasi.cmake" \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_C_COMPILER_LAUNCHER="$(which sccache)" \
    -D CMAKE_CXX_COMPILER_LAUNCHER="$(which sccache)" \
    -D CMAKE_INSTALL_PREFIX="$TARGET_TOOLCHAIN_DESTDIR/usr" \
    -D LLVM_BIN="$HOST_BUILD_DIR/llvm-$HOST_SUFFIX/bin" \
    -D LLVM_DIR="$LLVM_TARGET_BUILD_DIR/lib/cmake/llvm/" \
    -D LLVM_COMPILER_CHECKED=YES \
    -D UNIX=1 \
    -D SWIFT_NATIVE_SWIFT_TOOLS_PATH="$HOST_BUILD_DIR/swift-$HOST_SUFFIX/bin" \
    -D SWIFT_NATIVE_CLANG_TOOLS_PATH="$HOST_BUILD_DIR/llvm-$HOST_SUFFIX/bin" \
    -D SWIFT_NATIVE_LLVM_TOOLS_PATH="$HOST_BUILD_DIR/llvm-$HOST_SUFFIX/bin" \
    -D SWIFT_LIT_TEST_PATHS="$SWIFT_STDLIB_BUILD_DIR/test-wasi-wasm32/stdlib;$SWIFT_STDLIB_BUILD_DIR/test-wasi-wasm32/Concurrency/Runtime" \
    -D SWIFT_DRIVER_TEST_OPTIONS=" -Xclang-linker -resource-dir -Xclang-linker $COMPILER_RT_BUILD_DIR" \
    -D SWIFT_WASI_SYSROOT_PATH="$WASI_SYSROOT_PATH" \
    -D SWIFT_ENABLE_EXPERIMENTAL_DIFFERENTIABLE_PROGRAMMING=YES \
    -D SWIFT_ENABLE_EXPERIMENTAL_DISTRIBUTED=YES \
    -D SWIFT_ENABLE_EXPERIMENTAL_STRING_PROCESSING=YES \
    -D SWIFT_ENABLE_EXPERIMENTAL_REFLECTION=YES \
    -D SWIFT_PATH_TO_SWIFT_SYNTAX_SOURCE="$SOURCE_PATH/swift-syntax" \
    -D SWIFT_PATH_TO_STRING_PROCESSING_SOURCE="$SOURCE_PATH/swift-experimental-string-processing" \
    -G Ninja \
    -S "$SOURCE_PATH/swift"

  # FIXME(katei): 'sdk-overlay' is explicitly used to build libcxxshim.modulemap
  # which is used only in tests, so 'ninja install' doesn't build it
  # the header and modulemap custom targets should be added as dependency of install
  ninja sdk-overlay install -C "$SWIFT_STDLIB_BUILD_DIR"

  # Link compiler-rt libs to stdlib build dir
  mkdir -p "$SWIFT_STDLIB_BUILD_DIR/lib/clang/10.0.0/"
  ln -fs "$COMPILER_RT_BUILD_DIR/lib" "$SWIFT_STDLIB_BUILD_DIR/lib/clang/10.0.0/lib"

  # Remove host CoreFoundation module directory to avoid module conflict
  # while building Foundation
  rm -rf "$TARGET_TOOLCHAIN_DESTDIR/usr/lib/swift_static/CoreFoundation"
  "$TOOLS_BUILD_PATH/build-foundation.sh" "$TARGET_TOOLCHAIN_DESTDIR" "$WASI_SYSROOT_PATH"
  "$TOOLS_BUILD_PATH/build-xctest.sh" "$TARGET_TOOLCHAIN_DESTDIR" "$WASI_SYSROOT_PATH"

}

show_sccache_stats() {
  # If sccache is installed in PATH
  if command -v sccache &> /dev/null; then
    sccache --show-stats
  else
    echo "sccache is not installed in PATH"
  fi
}

if [ ${OPTIONS_BUILD_HOST_TOOLCHAIN} -eq 1 ]; then
  build_host_toolchain
  echo "=================================="
  echo "Host toolchain built successfully!"
  echo "=================================="
  echo ""
  echo "sccache stats:"
  show_sccache_stats
  rm -rf "$TARGET_TOOLCHAIN_DESTDIR"
  mkdir -p "$TARGET_TOOLCHAIN_DESTDIR"
  rsync -a "$HOST_TOOLCHAIN_DESTDIR/" "$TARGET_TOOLCHAIN_DESTDIR"
fi

build_target_toolchain
echo "===================================="
echo "Target toolchain built successfully!"
echo "===================================="
echo ""
echo "sccache stats:"
show_sccache_stats
