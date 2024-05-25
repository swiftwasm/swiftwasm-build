#!/bin/bash
set -ex
DESTINATION_TOOLCHAIN=$1
LLVM_BIN_DIR=$2
CLANG_BIN_DIR=$3
SWIFT_BIN_DIR=$4
WASI_SYSROOT_PATH=$5
TRIPLE="$6"

SOURCE_PATH="$(cd "$(dirname $0)/../../../.." && pwd)"
SCHEME_BUILD_PATH="$(cd "$(dirname $0)" && pwd)"
BUILD_SDK_PATH="$SOURCE_PATH/build-sdk"
LIBXML2_PATH="$BUILD_SDK_PATH/libxml2-$TRIPLE"

FOUNDATION_BUILD="$SOURCE_PATH/build/WebAssembly/foundation-$TRIPLE"

mkdir -p $FOUNDATION_BUILD
cd $FOUNDATION_BUILD

swift_extra_flags=""
c_extra_flags=""
if [[ "$TRIPLE" == "wasm32-unknown-wasip1-threads" ]]; then
  swift_extra_flags="-Xcc -matomics -Xcc -mbulk-memory -Xcc -mthread-model -Xcc posix -Xcc -pthread -Xcc -ftls-model=local-exec"
  c_extra_flags="-mthread-model posix -pthread -ftls-model=local-exec"
fi

cmake -G Ninja \
  -DCMAKE_BUILD_TYPE="Release" \
  -DCMAKE_SYSROOT="$WASI_SYSROOT_PATH" \
  -DCMAKE_Swift_COMPILER="$SWIFT_BIN_DIR/swiftc" \
  -DCMAKE_STAGING_PREFIX="$DESTINATION_TOOLCHAIN/usr" \
  -DCMAKE_TOOLCHAIN_FILE="$SCHEME_BUILD_PATH/toolchain-wasi.cmake" \
  -DTRIPLE="$TRIPLE" \
  -DLLVM_BIN="$LLVM_BIN_DIR" \
  -DCLANG_BIN="$CLANG_BIN_DIR" \
  -DICU_ROOT="$BUILD_SDK_PATH/icu-$TRIPLE" \
  -DLIBXML2_INCLUDE_DIR="$LIBXML2_PATH/include/libxml2" \
  -DLIBXML2_LIBRARY="$LIBXML2_PATH/lib" \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_NETWORKING=OFF \
  -DBUILD_TOOLS=OFF \
  -DFOUNDATION_ENABLE_FOUNDATION_NETWORKING=OFF \
  -DFOUNDATION_BUILD_TOOLS=OFF \
  -DHAS_LIBDISPATCH_API=OFF \
  -DCMAKE_Swift_COMPILER_FORCED=ON \
  -DCMAKE_Swift_FLAGS="-sdk $WASI_SYSROOT_PATH -resource-dir $DESTINATION_TOOLCHAIN/usr/lib/swift_static $swift_extra_flags" \
  -DCMAKE_C_FLAGS="-resource-dir $DESTINATION_TOOLCHAIN/usr/lib/swift_static/clang -B $LLVM_BIN_DIR $c_extra_flags" \
  "${SOURCE_PATH}/swift-corelibs-foundation"
  
ninja
ninja install
