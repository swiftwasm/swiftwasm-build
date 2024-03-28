#!/bin/bash
set -ex
DESTINATION_TOOLCHAIN=$1
LLVM_BIN_DIR=$2
CLANG_BIN_DIR=$3
SWIFT_BIN_DIR=$4
WASI_SYSROOT_PATH=$5

SOURCE_PATH="$(cd "$(dirname $0)/../../../../" && pwd)"
TOOLS_BUILD_PATH="$(cd "$(dirname "$0")/../../../tools/build" && pwd)"

BUILD_DIR="$SOURCE_PATH/build/WebAssembly/xctest-wasi-wasm32"

mkdir -p $BUILD_DIR
cd $BUILD_DIR

cmake -G Ninja \
  -DCMAKE_BUILD_TYPE="Release" \
  -DCMAKE_SYSROOT="$WASI_SYSROOT_PATH" \
  -DCMAKE_STAGING_PREFIX="$DESTINATION_TOOLCHAIN/usr" \
  -DCMAKE_Swift_COMPILER="$SWIFT_BIN_DIR/swiftc" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLS_BUILD_PATH/toolchain-wasi.cmake" \
  -DLLVM_BIN="$LLVM_BIN_DIR" \
  -DCLANG_BIN="$CLANG_BIN_DIR" \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_Swift_COMPILER_FORCED=ON \
  -DCMAKE_Swift_FLAGS="-sdk $WASI_SYSROOT_PATH -resource-dir $DESTINATION_TOOLCHAIN/usr/lib/swift_static" \
  -DSWIFT_FOUNDATION_PATH=$DESTINATION_TOOLCHAIN/usr/lib/swift_static/wasi/wasm32 \
  "${SOURCE_PATH}/swift-corelibs-xctest"
  
ninja -v
ninja -v install
