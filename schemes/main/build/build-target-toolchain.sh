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
TOOLS_BUILD_PATH="$(cd "$(dirname "$0")/../../../tools/build" && pwd)"
TARGET_BUILD_ROOT=$SOURCE_PATH/build/WebAssembly
PACKAGING_DIR="$SOURCE_PATH/build/Packaging"
TARGET_TOOLCHAIN_DESTDIR=$PACKAGING_DIR/target-toolchain

build_target_toolchain() {

  local LLVM_BIN_DIR="$1"
  local CLANG_BIN_DIR="$2"
  local SWIFT_BIN_DIR="$3"

  "$SOURCE_PATH/swift/utils/build-script" \
    --build-subdir=WebAssembly \
    --install-destdir="$TARGET_TOOLCHAIN_DESTDIR" \
    --release \
    --skip-build-llvm \
    --skip-build-swift \
    --skip-build-cmark \
    --skip-build-benchmarks \
    --skip-early-swift-driver \
    --build-wasm-stdlib \
    --skip-test-wasm-stdlib \
    --native-swift-tools-path="$SWIFT_BIN_DIR" \
    --native-clang-tools-path="$CLANG_BIN_DIR" \
    --native-llvm-tools-path="$LLVM_BIN_DIR" \
    --extra-cmake-options="\
      -DSWIFT_STDLIB_TRACING=NO \
      -DSWIFT_STDLIB_HAS_ASL=NO \
      -DSWIFT_STDLIB_CONCURRENCY_TRACING=NO \
      -DSWIFT_RUNTIME_CRASH_REPORTER_CLIENT=NO \
      -DSWIFT_STDLIB_INSTALL_PARENT_MODULE_FOR_SHIMS=NO \
      -DSWIFT_BUILD_DYNAMIC_SDK_OVERLAY=NO \
      -DSWIFT_BUILD_STATIC_SDK_OVERLAY=NO \
    " \
    --sccache

  local HOST_SUFFIX
  HOST_SUFFIX=$(find "$TARGET_BUILD_ROOT" -name "wasmstdlib-*" -exec basename {} \; | sed 's/wasmstdlib-//')

  env DESTDIR="$TARGET_TOOLCHAIN_DESTDIR" \
    cmake --install "$TARGET_BUILD_ROOT/wasmstdlib-$HOST_SUFFIX" --prefix /usr
    # cmake --install "$TARGET_BUILD_ROOT/wasmstdlib-linux-x86_64" --prefix /usr
  env DESTDIR="$TARGET_TOOLCHAIN_DESTDIR" \
    cmake --install "$TARGET_BUILD_ROOT/wasmthreadsstdlib-$HOST_SUFFIX" --prefix /usr
  env DESTDIR="$TARGET_TOOLCHAIN_DESTDIR/usr/lib/swift_static/clang" \
    cmake --install "$TARGET_BUILD_ROOT/wasmllvmruntimelibs-$HOST_SUFFIX" --component clang_rt.builtins-wasm32

  # FIXME: Clang resource directory installation is not the best way currently.
  # We currently have two copies of compiler headers copied from the base toolchain in
  # lib/swift/clang and lib/swift_static/clang. This is because the Swift CMake build
  # system installs the compiler headers from the native tools path when not building
  # tools including clang compiler. This is not ideal but then where should we bring
  # the compiler headers from? If we use the headers beside the base toolchain, clang
  # driver will not be able to find libclang_rt.builtins-wasm32.a because it is not
  # a part of the base toolchain. We need to find a better way to handle this.
  ln -sf ../../swift_static/clang "$TARGET_TOOLCHAIN_DESTDIR/usr/lib/swift/clang"
  # This empty directory is just to keep loose compatibility with swift-sdk-generator
  # because we still don't know the best way to handle the above issue.
  mkdir -p "$TARGET_TOOLCHAIN_DESTDIR/usr/lib/clang"

  local WASI_SYSROOT_PATH="$TARGET_BUILD_ROOT/wasi-sysroot"

  rsync -av "$WASI_SYSROOT_PATH/" "$PACKAGING_DIR/wasi-sysroot/"

  local CORELIBS_ARGS=(
    "$TARGET_TOOLCHAIN_DESTDIR"
    "$LLVM_BIN_DIR"
    "$CLANG_BIN_DIR"
    "$SWIFT_BIN_DIR"
    "$WASI_SYSROOT_PATH"
  )
  "$TOOLS_BUILD_PATH/build-foundation.sh" "${CORELIBS_ARGS[@]}"
  "$SCHEMES_BUILD_PATH/build-xctest.sh" "${CORELIBS_ARGS[@]}"
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

  build_target_toolchain "$OPTIONS_LLVM_BIN" "$OPTIONS_CLANG_BIN" "$OPTIONS_SWIFT_BIN" "$OPTIONS_SCHEME"
}

main "$@"
