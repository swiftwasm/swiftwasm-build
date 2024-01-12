#!/bin/bash
#
# Build the Swift standard library.

set -euo pipefail
set -x

print_help() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  --help               Display this help message."
  echo "  --llvm-bin           Path to LLVM bin directory."
  echo "  --swift-bin          Path to Swift bin directory."
}

SOURCE_PATH="$(cd "$(dirname "$0")/../../.." && pwd)"
TOOLS_BUILD_PATH="$(cd "$(dirname "$0")" && pwd)"
TARGET_BUILD_ROOT=$SOURCE_PATH/build/WebAssembly
PACKAGING_DIR="$SOURCE_PATH/build/Packaging"
TARGET_TOOLCHAIN_DESTDIR=$PACKAGING_DIR/target-toolchain
BUILD_SDK_PATH="$SOURCE_PATH/build-sdk"
WASI_SYSROOT_PATH="$BUILD_SDK_PATH/wasi-sysroot"

build_target_toolchain() {

  local LLVM_BIN_DIR="$1"
  local CLANG_BIN_DIR="$2"
  local SWIFT_BIN_DIR="$3"

  local COMPILER_RT_BUILD_DIR="$TARGET_BUILD_ROOT/compiler-rt-wasi-wasm32"
  local CLANG_VERSION
  CLANG_VERSION="$(basename "$($CLANG_BIN_DIR/clang -print-resource-dir)")"

  cmake -B "$COMPILER_RT_BUILD_DIR" \
    -D CMAKE_TOOLCHAIN_FILE="$TOOLS_BUILD_PATH/compiler-rt-cache.cmake" \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_C_COMPILER="$CLANG_BIN_DIR/clang" \
    -D CMAKE_CXX_COMPILER="$CLANG_BIN_DIR/clang++" \
    -D CMAKE_RANLIB="$LLVM_BIN_DIR/llvm-ranlib" \
    -D CMAKE_AR="$LLVM_BIN_DIR/llvm-ar" \
    -D CMAKE_C_COMPILER_LAUNCHER="$(which sccache)" \
    -D CMAKE_CXX_COMPILER_LAUNCHER="$(which sccache)" \
    -D CMAKE_INSTALL_PREFIX="$TARGET_TOOLCHAIN_DESTDIR/usr/lib/clang/$CLANG_VERSION/" \
    -D CMAKE_SYSROOT="${WASI_SYSROOT_PATH}" \
    -G Ninja \
    -S "$SOURCE_PATH/llvm-project/compiler-rt"

  ninja install -C "$COMPILER_RT_BUILD_DIR"

  local LLVM_TARGET_BUILD_DIR

  if [ -f "$SOURCE_PATH/build/llvm-tools/CMakeCache.txt" ]; then
    LLVM_TARGET_BUILD_DIR="$SOURCE_PATH/build/llvm-tools"
  else
    LLVM_TARGET_BUILD_DIR="$TARGET_BUILD_ROOT/llvm-wasi-wasm32"
    if [ ! -f "$LLVM_TARGET_BUILD_DIR/CMakeCache.txt" ]; then
      # Only configure LLVM to use CMake functionalities in LLVM
      cmake -B "$LLVM_TARGET_BUILD_DIR" \
        -D CMAKE_BUILD_TYPE=Release \
        -D LLVM_ENABLE_ZLIB=NO \
        -D LLVM_ENABLE_LIBXML2=NO \
        -D CMAKE_C_COMPILER="$CLANG_BIN_DIR/clang" \
        -D CMAKE_CXX_COMPILER="$CLANG_BIN_DIR/clang++" \
        -G Ninja \
        -S "$SOURCE_PATH/llvm-project/llvm"
    fi
  fi

  local SWIFT_STDLIB_BUILD_DIR="$TARGET_BUILD_ROOT/swift-stdlib-wasi-wasm32"

  # FIXME(katei): Platform/WASI is not recognized as a platform in LLVM, so it reports
  # "Unable to determine platform" while handling LLVM options.
  # Set WASI as a UNIX platform to spoof LLVM
  # FIXME(katei): host-build clang's libcxx is capable with LLVM, but it somehow
  # fails libcxx version check. So activate LLVM_COMPILER_CHECKED to spoof the checker
  # SWIFT_DRIVER_TEST_OPTIONS is used to specify clang resource dir for wasm32-unknown-wasi
  # because it's not built beside clang
  # TODO(katei): Move SWIFT_STDLIB_HAS_ASL and SWIFT_RUNTIME_CRASH_REPORTER_CLIENT
  # to cmake/caches/Runtime-WASI-wasm32.cmake
  cmake -B "$SWIFT_STDLIB_BUILD_DIR" \
    -C "$SOURCE_PATH/swift/cmake/caches/Runtime-WASI-wasm32.cmake" \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_C_COMPILER_LAUNCHER="$(which sccache)" \
    -D CMAKE_CXX_COMPILER_LAUNCHER="$(which sccache)" \
    -D CMAKE_C_COMPILER="$CLANG_BIN_DIR/clang" \
    -D CMAKE_CXX_COMPILER="$CLANG_BIN_DIR/clang++" \
    -D CMAKE_RANLIB="$LLVM_BIN_DIR/llvm-ranlib" \
    -D CMAKE_AR="$LLVM_BIN_DIR/llvm-ar" \
    -D CMAKE_INSTALL_PREFIX="$TARGET_TOOLCHAIN_DESTDIR/usr" \
    -D LLVM_DIR="$LLVM_TARGET_BUILD_DIR/lib/cmake/llvm/" \
    -D LLVM_COMPILER_CHECKED=YES \
    -D UNIX=1 \
    -D SWIFT_NATIVE_SWIFT_TOOLS_PATH="$SWIFT_BIN_DIR" \
    -D SWIFT_NATIVE_CLANG_TOOLS_PATH="$CLANG_BIN_DIR" \
    -D SWIFT_NATIVE_LLVM_TOOLS_PATH="$LLVM_BIN_DIR" \
    -D SWIFT_LIT_TEST_PATHS="$SWIFT_STDLIB_BUILD_DIR/test-wasi-wasm32/stdlib;$SWIFT_STDLIB_BUILD_DIR/test-wasi-wasm32/Concurrency/Runtime" \
    -D SWIFT_DRIVER_TEST_OPTIONS=" -Xclang-linker -resource-dir -Xclang-linker $COMPILER_RT_BUILD_DIR" \
    -D SWIFT_WASI_SYSROOT_PATH="$WASI_SYSROOT_PATH" \
    -D SWIFT_WASI_wasm32_ICU_UC_INCLUDE="$BUILD_SDK_PATH/icu/include" \
    -D SWIFT_WASI_wasm32_ICU_UC="$BUILD_SDK_PATH/icu/lib/libicuuc.a" \
    -D SWIFT_WASI_wasm32_ICU_I18N_INCLUDE="$BUILD_SDK_PATH/icu/include" \
    -D SWIFT_WASI_wasm32_ICU_I18N="$BUILD_SDK_PATH/icu/lib/libicui18n.a" \
    -D SWIFT_WASI_wasm32_ICU_DATA="$BUILD_SDK_PATH/icu/lib/libicudata.a" \
    -D SWIFT_ENABLE_DISPATCH=NO \
    -D SWIFT_ENABLE_EXPERIMENTAL_DIFFERENTIABLE_PROGRAMMING=YES \
    -D SWIFT_ENABLE_EXPERIMENTAL_DISTRIBUTED=YES \
    -D SWIFT_ENABLE_EXPERIMENTAL_STRING_PROCESSING=YES \
    -D SWIFT_ENABLE_EXPERIMENTAL_REFLECTION=YES \
    -D SWIFT_PRIMARY_VARIANT_SDK=WASI \
    -D SWIFT_PRIMARY_VARIANT_ARCH=wasm32 \
    -D SWIFT_SDKS:STRING=WASI \
    -D SWIFT_STDLIB_HAS_ASL=NO \
    -D SWIFT_STDLIB_TRACING=NO \
    -D SWIFT_STDLIB_CONCURRENCY_TRACING=NO \
    -D SWIFT_RUNTIME_CRASH_REPORTER_CLIENT=NO \
    -D SWIFT_STDLIB_INSTALL_PARENT_MODULE_FOR_SHIMS=NO \
    -D SWIFT_BUILD_DYNAMIC_SDK_OVERLAY=NO \
    -D SWIFT_BUILD_STATIC_SDK_OVERLAY=NO \
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

  local CORELIBS_ARGS=(
    "$TARGET_TOOLCHAIN_DESTDIR"
    "$LLVM_BIN_DIR"
    "$CLANG_BIN_DIR"
    "$SWIFT_BIN_DIR"
    "$WASI_SYSROOT_PATH"
  )
  "$TOOLS_BUILD_PATH/build-foundation.sh" "${CORELIBS_ARGS[@]}"
  "$TOOLS_BUILD_PATH/build-xctest.sh" "${CORELIBS_ARGS[@]}"

}

main() {
  local OPTIONS_LLVM_BIN=""
  local OPTIONS_CLANG_BIN=""
  local OPTIONS_SWIFT_BIN=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --llvm-bin)
        OPTIONS_LLVM_BIN="$2"
        shift 2
        ;;
      --clang-bin)
        OPTIONS_CLANG_BIN="$2"
        shift 2
        ;;
      --swift-bin)
        OPTIONS_SWIFT_BIN="$2"
        shift 2
        ;;
      --help)
        print_help
        exit 0
        ;;
      *)
        echo "Unknown option: $1"
        print_help
        exit 1
        ;;
    esac
  done

  if [[ -z "$OPTIONS_LLVM_BIN" ]]; then
    echo "Missing --llvm-bin option"
    print_help
    exit 1
  fi

  if [[ -z "$OPTIONS_SWIFT_BIN" ]]; then
    echo "Missing --swift-bin option"
    print_help
    exit 1
  fi

  if [[ -z "$OPTIONS_CLANG_BIN" ]]; then
    OPTIONS_CLANG_BIN="$OPTIONS_LLVM_BIN"
  fi

  build_target_toolchain "$OPTIONS_LLVM_BIN" "$OPTIONS_CLANG_BIN" "$OPTIONS_SWIFT_BIN"
}

main "$@"
