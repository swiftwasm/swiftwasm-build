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

SCHEMES_BUILD_PATH="$(cd "$(dirname "$0")" && pwd)"
SOURCE_PATH="$(cd "$(dirname "$0")/../../../.." && pwd)"
TARGET_BUILD_ROOT=$SOURCE_PATH/build/WebAssembly
WASI_SYSROOT_PATH="$TARGET_BUILD_ROOT/wasi-sysroot"
PACKAGING_DIR="$SOURCE_PATH/build/Packaging"
TARGET_TOOLCHAIN_DESTDIR=$PACKAGING_DIR/target-toolchain

build_target_toolchain() {

  local LLVM_BIN_DIR="$1"
  local CLANG_BIN_DIR="$2"
  local SWIFT_BIN_DIR="$3"
  local TRIPLE="$4"
  local STDLIB_PRODUCT="$5"
  local COMPILER_RT_OS_DIR="$6"

  local HOST_SUFFIX
  HOST_SUFFIX=$(find "$TARGET_BUILD_ROOT" -name "wasmstdlib-*" -exec basename {} \; | sed 's/wasmstdlib-//')

  local TRIPLE_DESTDIR="$TARGET_TOOLCHAIN_DESTDIR/$TRIPLE"

  env DESTDIR="$TRIPLE_DESTDIR" \
    cmake --install "$TARGET_BUILD_ROOT/$STDLIB_PRODUCT-$HOST_SUFFIX" --prefix /usr

  rm -rf "$TRIPLE_DESTDIR/usr/lib/swift_static/clang/lib/$COMPILER_RT_OS_DIR"
  # XXX: Is this the right way to install compiler-rt?
  cp -R "$TARGET_BUILD_ROOT/wasi-sysroot/lib/$COMPILER_RT_OS_DIR" "$TRIPLE_DESTDIR/usr/lib/swift_static/clang/lib/$COMPILER_RT_OS_DIR"

  # FIXME: Clang resource directory installation is not the best way currently.
  # We currently have two copies of compiler headers copied from the base toolchain in
  # lib/swift/clang and lib/swift_static/clang. This is because the Swift CMake build
  # system installs the compiler headers from the native tools path when not building
  # tools including clang compiler. This is not ideal but then where should we bring
  # the compiler headers from? If we use the headers beside the base toolchain, clang
  # driver will not be able to find libclang_rt.builtins-wasm32.a because it is not
  # a part of the base toolchain. We need to find a better way to handle this.
  local CLANG_VERSION
  CLANG_VERSION="$(basename "$($CLANG_BIN_DIR/clang -print-resource-dir)")"
  mkdir -p "$TRIPLE_DESTDIR/usr/lib/clang/$CLANG_VERSION/lib"
  ln -sf "../../../swift_static/clang/lib/$COMPILER_RT_OS_DIR" "$TRIPLE_DESTDIR/usr/lib/clang/$CLANG_VERSION/lib/$COMPILER_RT_OS_DIR"
}

build_target_corelibs() {
  local LLVM_BIN_DIR="$1"
  local CLANG_BIN_DIR="$2"
  local SWIFT_BIN_DIR="$3"
  local TRIPLE="$4"

  local TRIPLE_DESTDIR="$TARGET_TOOLCHAIN_DESTDIR/$TRIPLE"
  local CORELIBS_ARGS=(
    "$TRIPLE_DESTDIR"
    "$LLVM_BIN_DIR"
    "$CLANG_BIN_DIR"
    "$SWIFT_BIN_DIR"
    "$WASI_SYSROOT_PATH"
  )
  "$SCHEMES_BUILD_PATH/build-foundation.sh" "${CORELIBS_ARGS[@]}" "$TRIPLE"
  "$SCHEMES_BUILD_PATH/build-xctest.sh" "${CORELIBS_ARGS[@]}" "$TRIPLE"
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
      --scheme)
        OPTIONS_SCHEME="$2"
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

  # NOTE: The llvm-cmake-options is a workaround for the issue on amazonlinux2
  # See https://github.com/apple/swift/commit/40c7268e8f7d402b27e3ad16a84180e07c37f92c
  "$SOURCE_PATH/swift/utils/build-script" \
    --build-subdir=WebAssembly \
    --release \
    --skip-build-llvm \
    --skip-build-swift \
    --skip-build-cmark \
    --skip-build-benchmarks \
    --skip-early-swift-driver \
    --build-wasm-stdlib \
    --skip-test-wasm-stdlib \
    --native-swift-tools-path="$OPTIONS_SWIFT_BIN" \
    --native-clang-tools-path="$OPTIONS_CLANG_BIN" \
    --native-llvm-tools-path="$OPTIONS_LLVM_BIN" \
    --extra-cmake-options="\
      -DSWIFT_STDLIB_TRACING=NO \
      -DSWIFT_STDLIB_HAS_ASL=NO \
      -DSWIFT_STDLIB_CONCURRENCY_TRACING=NO \
      -DSWIFT_RUNTIME_CRASH_REPORTER_CLIENT=NO \
      -DSWIFT_STDLIB_INSTALL_PARENT_MODULE_FOR_SHIMS=NO \
      -DSWIFT_BUILD_DYNAMIC_SDK_OVERLAY=NO \
      -DSWIFT_BUILD_STATIC_SDK_OVERLAY=NO \
    " \
    --llvm-cmake-options="\
      -DCROSS_TOOLCHAIN_FLAGS_LLVM_NATIVE='-DCMAKE_C_COMPILER=clang;-DCMAKE_CXX_COMPILER=clang++' \
    " \
    --sccache

  local BUILD_TOOLS_ARGS=(
    "$OPTIONS_LLVM_BIN"
    "$OPTIONS_CLANG_BIN"
    "$OPTIONS_SWIFT_BIN"
  )

  build_target_toolchain "${BUILD_TOOLS_ARGS[@]}" "wasm32-wasi" "wasmstdlib" "wasi"
  build_target_toolchain "${BUILD_TOOLS_ARGS[@]}" "wasm32-wasip1-threads" "wasmthreadsstdlib" "wasip1"

  rsync -av "$WASI_SYSROOT_PATH/" "$PACKAGING_DIR/wasi-sysroot/"

  build_target_corelibs "${BUILD_TOOLS_ARGS[@]}" "wasm32-wasi"
  build_target_corelibs "${BUILD_TOOLS_ARGS[@]}" "wasm32-wasip1-threads"
}

main "$@"
