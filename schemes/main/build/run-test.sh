#!/bin/bash

set -euxo pipefail

SOURCE_PATH="$(cd "$(dirname "$0")/../../../.." && pwd)"
BUILD_DIR="$SOURCE_PATH/build"
TARGET_BUILD_ROOT="$BUILD_DIR/WebAssembly"

HOST_SUFFIX=$(find "$TARGET_BUILD_ROOT" -name "wasmstdlib-*" -exec basename {} \; | sed 's/wasmstdlib-//')
env "PATH=$TARGET_BUILD_ROOT/llvm-$HOST_SUFFIX/bin:$BUILD_DIR/llvm-tools/bin:$PATH" "LIT_FILTER_OUT=(IRGen/|embedded/)" ninja check-swift-wasi-wasm32-custom -C "$TARGET_BUILD_ROOT/wasmstdlib-$HOST_SUFFIX"
