#!/bin/bash
set -ex
DESTINATION_TOOLCHAIN=$1
LLVM_BIN_DIR=$2
CLANG_BIN_DIR=$3
SWIFT_BIN_DIR=$4
WASI_SYSROOT_PATH=$5
TRIPLE="$6"

SOURCE_PATH="$(cd "$(dirname $0)/../../../../" && pwd)"
SCHEME_BUILD_PATH="$(cd "$(dirname $0)" && pwd)"

BUILD_DIR="$SOURCE_PATH/build/WebAssembly/xctest-$TRIPLE"

mkdir -p $BUILD_DIR
cd $BUILD_DIR

swift_extra_flags=""
if [[ "$TRIPLE" == "wasm32-unknown-wasip1-threads" ]]; then
  swift_extra_flags="-Xcc -matomics -Xcc -mbulk-memory -Xcc -mthread-model -Xcc posix -Xcc -pthread -Xcc -ftls-model=local-exec"
fi

cmake -G Ninja \
  -DCMAKE_BUILD_TYPE="Release" \
  -DCMAKE_SYSROOT="$WASI_SYSROOT_PATH" \
  -DCMAKE_STAGING_PREFIX="$DESTINATION_TOOLCHAIN/usr" \
  -DCMAKE_Swift_COMPILER="$SWIFT_BIN_DIR/swiftc" \
  -DCMAKE_TOOLCHAIN_FILE="$SCHEME_BUILD_PATH/toolchain-wasi.cmake" \
  -DTRIPLE="$TRIPLE" \
  -DLLVM_BIN="$LLVM_BIN_DIR" \
  -DCLANG_BIN="$CLANG_BIN_DIR" \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_Swift_COMPILER_FORCED=ON \
  -DCMAKE_Swift_FLAGS="-sdk $WASI_SYSROOT_PATH -resource-dir $DESTINATION_TOOLCHAIN/usr/lib/swift_static $swift_extra_flags" \
  -DSWIFT_FOUNDATION_PATH=$DESTINATION_TOOLCHAIN/usr/lib/swift_static/wasi/wasm32 \
  "${SOURCE_PATH}/swift-corelibs-xctest"
  
ninja -v
ninja -v install
