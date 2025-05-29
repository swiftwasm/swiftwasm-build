#!/bin/bash
set -ex
DESTINATION_TOOLCHAIN=$1
LLVM_BIN_DIR=$2
CLANG_BIN_DIR=$3
SWIFT_BIN_DIR=$4
WASI_SYSROOT_PATH=$5
TRIPLE="$6"

SOURCE_PATH="$(cd "$(dirname $0)/../../../.." && pwd)"
BUILD_SDK_PATH="$SOURCE_PATH/build-sdk"
LIBXML2_PATH="$BUILD_SDK_PATH/libxml2-$TRIPLE"

FOUNDATION_BUILD="$SOURCE_PATH/build/WebAssembly/foundation-$TRIPLE"

swift_extra_flags=""
c_extra_flags=""
if [[ "$TRIPLE" == "wasm32-unknown-wasip1-threads" ]]; then
  swift_extra_flags="-Xcc -matomics -Xcc -mbulk-memory -Xcc -mthread-model -Xcc posix -Xcc -pthread -Xcc -ftls-model=local-exec"
  c_extra_flags="-mthread-model posix -pthread -ftls-model=local-exec"
fi

cmake -G Ninja \
  -D CMAKE_BUILD_TYPE="Release" \
  -D CMAKE_SYSROOT="$WASI_SYSROOT_PATH" \
  -D CMAKE_Swift_COMPILER="$SWIFT_BIN_DIR/swiftc" \
  -D CMAKE_STAGING_PREFIX="$DESTINATION_TOOLCHAIN/usr" \
  -D CMAKE_SYSTEM_NAME=WASI \
  -D CMAKE_SYSTEM_PROCESSOR=wasm32 \
  -D CMAKE_C_COMPILER_TARGET="$TRIPLE" \
  -D CMAKE_CXX_COMPILER_TARGET="$TRIPLE" \
  -D CMAKE_Swift_COMPILER_TARGET="$TRIPLE" \
  -D CMAKE_C_COMPILER="$CLANG_BIN_DIR/clang" \
  -D CMAKE_CXX_COMPILER="$CLANG_BIN_DIR/clang++" \
  -D CMAKE_AR="$LLVM_BIN_DIR/llvm-ar" \
  -D CMAKE_RANLIB="$LLVM_BIN_DIR/llvm-ranlib" \
  -D LIBXML2_INCLUDE_DIR="$LIBXML2_PATH/include/libxml2" \
  -D LIBXML2_LIBRARY="$LIBXML2_PATH/lib" \
  -D BUILD_SHARED_LIBS=OFF \
  -D FOUNDATION_BUILD_TOOLS=OFF \
  -D CMAKE_Swift_COMPILER_FORCED=ON \
  -D CMAKE_C_COMPILER_FORCED=ON \
  -D CMAKE_CXX_COMPILER_FORCED=ON \
  -D CMAKE_Swift_FLAGS="-sdk $WASI_SYSROOT_PATH -resource-dir $DESTINATION_TOOLCHAIN/usr/lib/swift_static $swift_extra_flags" \
  -D CMAKE_C_FLAGS="-resource-dir $DESTINATION_TOOLCHAIN/usr/lib/swift_static/clang -B $LLVM_BIN_DIR $c_extra_flags" \
  -D CMAKE_CXX_FLAGS="-fno-exceptions -resource-dir $DESTINATION_TOOLCHAIN/usr/lib/swift_static/clang -B $LLVM_BIN_DIR $c_extra_flags" \
  -D _SwiftCollections_SourceDIR="$SOURCE_PATH/swift-collections" \
  -D _SwiftFoundation_SourceDIR="$SOURCE_PATH/swift-foundation" \
  -D _SwiftFoundationICU_SourceDIR="$SOURCE_PATH/swift-foundation-icu" \
  -D SwiftFoundation_MACRO="$SWIFT_BIN_DIR/../lib/swift/host/plugins" \
  -B "$FOUNDATION_BUILD" \
  "${SOURCE_PATH}/swift-corelibs-foundation"
  
cmake --build "$FOUNDATION_BUILD"
cmake --install "$FOUNDATION_BUILD"
