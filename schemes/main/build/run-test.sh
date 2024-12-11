#!/bin/bash

set -euxo pipefail

SOURCE_PATH="$(cd "$(dirname "$0")/../../../.." && pwd)"
TARGET_BUILD_ROOT="$SOURCE_PATH/build/WebAssembly"

HOST_SUFFIX=$(find "$TARGET_BUILD_ROOT" -name "wasmstdlib-*" -exec basename {} \; | sed 's/wasmstdlib-//')
# Force using the new driver for testing until https://github.com/swiftlang/swift-driver/pull/1756
env SWIFT_FORCE_TEST_NEW_DRIVER=1 "PATH=$TARGET_BUILD_ROOT/llvm-$HOST_SUFFIX/bin:$PATH" "LIT_FILTER_OUT=(IRGen/|embedded/)" ninja check-swift-wasi-wasm32-custom -C "$TARGET_BUILD_ROOT/wasmstdlib-$HOST_SUFFIX"
