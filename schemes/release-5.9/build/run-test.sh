#!/bin/bash

set -euxo pipefail

SOURCE_PATH="$(cd "$(dirname "$0")/../../../.." && pwd)"
TARGET_BUILD_ROOT="$SOURCE_PATH/build/WebAssembly"

ninja check-swift-wasi-wasm32-custom -C "$TARGET_BUILD_ROOT/swift-stdlib-wasi-wasm32"
