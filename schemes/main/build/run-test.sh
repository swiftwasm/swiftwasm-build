#!/bin/bash

set -euxo pipefail

SOURCE_PATH="$(cd "$(dirname "$0")/../../../.." && pwd)"
TARGET_BUILD_ROOT="$SOURCE_PATH/build/WebAssembly"

env "LIT_FILTER_OUT=(IRGen/|embedded/)"
ninja check-swift-wasi-wasm32-custom -C "$TARGET_BUILD_ROOT/wasmstdlib-linux-x86_64"
