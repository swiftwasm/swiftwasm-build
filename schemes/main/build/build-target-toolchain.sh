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

  local TRIPLE="$4"

  local HOST_SUFFIX
  HOST_SUFFIX=$(find "$TARGET_BUILD_ROOT" -name "wasistdlib-*" -exec basename {} \; | sed 's/wasistdlib-//')

  local TRIPLE_DESTDIR="$TARGET_TOOLCHAIN_DESTDIR/$TRIPLE"

  rm -rf "$TRIPLE_DESTDIR"
  mkdir -p "$TRIPLE_DESTDIR"
  cp -R "$TARGET_BUILD_ROOT/wasiswiftsdk-$HOST_SUFFIX/Toolchains/$TRIPLE/usr" "$TRIPLE_DESTDIR/usr"
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

  # Standard library CMake options shared by every flavour of the Swift SDK.
  # `--extra-cmake-options` is appended last to the WASI stdlib configure, so
  # these override the defaults in swift's wasmstdlibhelpers.py.
  local EXTRA_CMAKE_OPTIONS="\
      -DSWIFT_STDLIB_TRACING=NO \
      -DSWIFT_STDLIB_HAS_ASL=NO \
      -DSWIFT_STDLIB_CONCURRENCY_TRACING=NO \
      -DSWIFT_RUNTIME_CRASH_REPORTER_CLIENT=NO \
      -DSWIFT_STDLIB_INSTALL_PARENT_MODULE_FOR_SHIMS=NO \
    "

  # Extra `utils/build-script` arguments used only by the hermetic full-LTO
  # flavour. Empty for the default flavour.
  local HERMETIC_LTO_BUILD_SCRIPT_ARGS=()

  # Hermetic full-LTO flavour of the Swift SDK, enabled by SWIFTWASM_HERMETIC_LTO=1.
  # See docs/hermetic-lto-sdk.md. When the variable is not "1", the
  # `utils/build-script` invocation below is identical to the default one.
  if [[ "${SWIFTWASM_HERMETIC_LTO:-}" == "1" ]]; then
    EXTRA_CMAKE_OPTIONS+="\
      -DSWIFT_STDLIB_ENABLE_LTO=full \
      -DSWIFT_STDLIB_EXPERIMENTAL_HERMETIC_SEAL_AT_LINK=TRUE \
      -DSWIFT_STDLIB_STABLE_ABI=FALSE \
    "
    # Extend the flavour to the Foundation stack (corelibs-foundation with the
    # swift-foundation sources, CoreFoundation, FoundationICU, libxml2). These
    # options come from the carried patch
    # schemes/main/swift/0002-build-script-Add-WASI-Swift-SDK-LTO-options.patch;
    # SWIFT_STDLIB_ENABLE_LTO alone never reaches those separate CMake projects.
    #
    # The Foundation stack is shipped as bitcode but is NOT hermetically sealed:
    # `--wasi-swift-sdk-hermetic-seal-at-link` makes the pinned snapshot's
    # swift-frontend assert in `typeIdForMethod` (GenClass.cpp) while emitting
    # the virtual-method type id for NSMutableDictionary's overridden
    # `init(sharedKeySet:)` in swift-corelibs-foundation. The standard library
    # and the runtime are still sealed. See docs/hermetic-lto-sdk.md.
    #
    # TODO: add `--wasi-swift-sdk-hermetic-seal-at-link` here once the pinned
    # base snapshot in schemes/main/manifest.json contains BOTH of these
    # swift-frontend fixes. Sealing Foundation needs both; either one alone
    # still aborts the compile, and both are assertion-only changes:
    #
    #   1. `typeIdForMethod` (lib/IRGen/GenClass.cpp) asserted
    #      `!method.getOverridden()`. A `required` convenience initializer that
    #      overrides a non-required, non-designated convenience initializer
    #      introduces its own vtable slot, so it *is* the base method of that
    #      slot. The fix asserts `method == method.getOverriddenVTableEntry()`.
    #      Hit on NSDictionary.swift (`NSMutableDictionary.init()`).
    #
    #   2. `ClassContextDescriptorBuilder::addVTableTypeMetadata`
    #      (lib/IRGen/GenMeta.cpp) asserted `VTable && "no vtable?!"`. A
    #      foreign class -- an imported CF type -- has no Swift vtable and
    #      collects no method descriptors, so the call has nothing to do. The
    #      fix skips it for `getType()->isForeign()`.
    #      Hit on NSLocale.swift (`CFLocale`).
    #
    # Both are verified with an assertions-enabled frontend and a real sealed
    # Foundation build; see the "Status with the pending compiler fixes"
    # section of docs/hermetic-lto-sdk.md. A quick check that a candidate
    # snapshot has fix 1, on any host, with no wasm SDK and no seal involved:
    #
    #   cat > t.swift <<'EOF'
    #   class B { init(x: Int) {}
    #             convenience init() { self.init(x: 0) } }
    #   class D: B { required convenience init() { self.init(x: 1) } }
    #   EOF
    #   swiftc -Xfrontend -enable-llvm-vfe -emit-ir t.swift -o /dev/null
    #
    # It exits 0 with the fix and aborts without it. Fix 2 needs a CF-bridged
    # typedef plus a metatype reference; see the docs section.
    HERMETIC_LTO_BUILD_SCRIPT_ARGS+=(
      --wasi-swift-sdk-lto=full
    )
  fi

  # NOTE: The llvm-cmake-options is a workaround for the issue on amazonlinux2
  # See https://github.com/apple/swift/commit/40c7268e8f7d402b27e3ad16a84180e07c37f92c
  # NOTE: Add llvm-bin directory to PATH so that wasistdlib.py can find FileCheck during tests
  env PATH="$OPTIONS_LLVM_BIN:$OPTIONS_SWIFT_BIN:$PATH" "$SOURCE_PATH/swift/utils/build-script" \
    --build-subdir=WebAssembly \
    --release \
    --skip-build-llvm \
    --skip-build-swift \
    --skip-build-cmark \
    --skip-build-benchmarks \
    --skip-early-swift-driver \
    --skip-test-wasi-stdlib \
    --wasmkit \
    --build-wasi-stdlib \
    --skip-test-wasi-stdlib \
    --native-swift-tools-path="$OPTIONS_SWIFT_BIN" \
    --native-clang-tools-path="$OPTIONS_CLANG_BIN" \
    --native-llvm-tools-path="$OPTIONS_LLVM_BIN" \
    --build-runtime-with-host-compiler \
    --extra-cmake-options="$EXTRA_CMAKE_OPTIONS" \
    --llvm-cmake-options="\
      -DCROSS_TOOLCHAIN_FLAGS_LLVM_NATIVE='-DCMAKE_C_COMPILER=clang;-DCMAKE_CXX_COMPILER=clang++' \
    " \
    --sccache \
    ${HERMETIC_LTO_BUILD_SCRIPT_ARGS[@]+"${HERMETIC_LTO_BUILD_SCRIPT_ARGS[@]}"}

  local BUILD_TOOLS_ARGS=(
    "$OPTIONS_LLVM_BIN"
    "$OPTIONS_CLANG_BIN"
    "$OPTIONS_SWIFT_BIN"
  )

  build_target_toolchain "${BUILD_TOOLS_ARGS[@]}" "wasm32-unknown-wasip1" "wasip1-wasm32" "wasm32-wasip1" "wasistdlib" "wasip1"
  build_target_toolchain "${BUILD_TOOLS_ARGS[@]}" "wasm32-unknown-wasip1-threads" "wasip1-threads-wasm32" "wasm32-wasip1-threads" "wasithreadsstdlib" "wasip1"

  rsync -av "$WASI_SYSROOT_PATH/" "$PACKAGING_DIR/wasi-sysroot/"
}

main "$@"
