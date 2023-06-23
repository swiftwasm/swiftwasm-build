#!/bin/bash

set -ex
SOURCE_PATH="$(cd "$(dirname "$0")/../../.." && pwd)"
TOOLS_BUILD_PATH="$(cd "$(dirname "$0")" && pwd)"

BUILD_SDK_PATH="$SOURCE_PATH/build-sdk"
WASI_SYSROOT_PATH="$BUILD_SDK_PATH/wasi-sysroot"

case $(uname -s) in
  Darwin)
    OS_SUFFIX=macos_$(uname -m)
    HOST_PRESET=webassembly-host-install
    HOST_SUFFIX=macosx-$(uname -m)
  ;;
  Linux)
    if [ "$(grep RELEASE /etc/lsb-release)" == "DISTRIB_RELEASE=18.04" ]; then
      OS_SUFFIX=ubuntu18.04_$(uname -m)
    elif [ "$(grep RELEASE /etc/lsb-release)" == "DISTRIB_RELEASE=20.04" ]; then
      OS_SUFFIX=ubuntu20.04_$(uname -m)
    elif [ "$(grep RELEASE /etc/lsb-release)" == "DISTRIB_RELEASE=22.04" ]; then
      OS_SUFFIX=ubuntu22.04_$(uname -m)
    elif [[ "$(grep PRETTY_NAME /etc/os-release)" == 'PRETTY_NAME="Amazon Linux 2"' ]]; then
      OS_SUFFIX=amazonlinux2_$(uname -m)
    else
      echo "Unknown Ubuntu version"
      exit 1
    fi
    HOST_PRESET=webassembly-linux-host-install
    HOST_SUFFIX=linux-$(uname -m)
  ;;
  *)
    echo "Unrecognised platform $(uname -s)"
    exit 1
  ;;
esac

OPTIONS_BUILD_HOST_TOOLCHAIN=1
OPTIONS_DAILY_SNAPSHOT=0
TOOLCHAIN_CHANNEL=${TOOLCHAIN_CHANNEL:-DEVELOPMENT}

while [ $# -ne 0 ]; do
  case "$1" in
    --skip-build-host-toolchain)
    OPTIONS_BUILD_HOST_TOOLCHAIN=0
  ;;
    --daily-snapshot)
    OPTIONS_DAILY_SNAPSHOT=1
  ;;
  *)
    echo "Unrecognised argument \"$1\""
    exit 1
  ;;
  esac
  shift
done

YEAR=$(date +"%Y")
MONTH=$(date +"%m")
DAY=$(date +"%d")

if [ ${OPTIONS_DAILY_SNAPSHOT} -eq 1 ]; then
  TOOLCHAIN_NAME="swift-wasm-${TOOLCHAIN_CHANNEL}-SNAPSHOT-${YEAR}-${MONTH}-${DAY}-a"
else
  TOOLCHAIN_NAME="swift-wasm-${TOOLCHAIN_CHANNEL}-SNAPSHOT"
fi

PACKAGE_ARTIFACT="$SOURCE_PATH/swift-wasm-${TOOLCHAIN_CHANNEL}-SNAPSHOT-${OS_SUFFIX}.tar.gz"

PACKAGING_DIR="$SOURCE_PATH/build/Packaging"
HOST_TOOLCHAIN_DESTDIR=$PACKAGING_DIR/host-toolchain
TARGET_TOOLCHAIN_DESTDIR=$PACKAGING_DIR/target-toolchain

HOST_BUILD_ROOT=$SOURCE_PATH/build/WebAssemblyCompiler
TARGET_BUILD_ROOT=$SOURCE_PATH/build/WebAssemblyStdlib
HOST_BUILD_DIR=$HOST_BUILD_ROOT/Ninja-ReleaseAssert

build_host_toolchain() {
  # Build the host toolchain and SDK first.
  env SWIFT_BUILD_ROOT="$HOST_BUILD_ROOT" \
    "$SOURCE_PATH/swift/utils/build-script" \
    --preset-file="$TOOLS_BUILD_PATH/build-presets.ini" \
    --preset=$HOST_PRESET \
    --build-dir="$HOST_BUILD_DIR" \
    HOST_ARCHITECTURE="$(uname -m)" \
    INSTALL_DESTDIR="$HOST_TOOLCHAIN_DESTDIR"
}

build_target_toolchain() {

  local COMPILER_RT_BUILD_DIR="$TARGET_BUILD_ROOT/compiler-rt-wasi-wasm32"
  cmake -B "$COMPILER_RT_BUILD_DIR" \
    -D CMAKE_TOOLCHAIN_FILE="$TOOLS_BUILD_PATH/compiler-rt-cache.cmake" \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_C_COMPILER="$HOST_BUILD_DIR/llvm-$HOST_SUFFIX/bin/clang" \
    -D CMAKE_CXX_COMPILER="$HOST_BUILD_DIR/llvm-$HOST_SUFFIX/bin/clang++" \
    -D CMAKE_RANLIB="$HOST_BUILD_DIR/llvm-$HOST_SUFFIX/bin/llvm-ranlib" \
    -D CMAKE_AR="$HOST_BUILD_DIR/llvm-$HOST_SUFFIX/bin/llvm-ar" \
    -D CMAKE_C_COMPILER_LAUNCHER="$(which sccache)" \
    -D CMAKE_CXX_COMPILER_LAUNCHER="$(which sccache)" \
    -D CMAKE_INSTALL_PREFIX="$TARGET_TOOLCHAIN_DESTDIR/usr/lib/clang/13.0.0/" \
    -D CMAKE_SYSROOT="${WASI_SYSROOT_PATH}" \
    -G Ninja \
    -S "$SOURCE_PATH/llvm-project/compiler-rt"

  ninja install -C "$COMPILER_RT_BUILD_DIR"

  # Only configure LLVM to use CMake functionalities in LLVM
  local LLVM_TARGET_BUILD_DIR="$TARGET_BUILD_ROOT/llvm-wasi-wasm32"
  cmake -B "$LLVM_TARGET_BUILD_DIR" \
    -D CMAKE_BUILD_TYPE=Release \
    -D LLVM_ENABLE_ZLIB=NO \
    -D LLVM_ENABLE_LIBXML2=NO \
    -G Ninja \
    -S "$SOURCE_PATH/llvm-project/llvm"

  local SWIFT_STDLIB_BUILD_DIR="$TARGET_BUILD_ROOT/swift-stdlib-wasi-wasm32"

  # FIXME(katei): Platform/WASI is not recognized as a platform in LLVM, so it reports
  # "Unable to determine platform" while handling LLVM options.
  # Set WASI as a UNIX platform to spoof LLVM
  # FIXME(katei): host-build clang's libcxx is capable with LLVM, but it somehow
  # fails libcxx version check. So activate LLVM_COMPILER_CHECKED to spoof the checker
  # SWIFT_DRIVER_TEST_OPTIONS is used to specify clang resource dir for wasm32-unknown-wasi
  # because it's not built beside clang
  cmake -B "$SWIFT_STDLIB_BUILD_DIR" \
    -C "$SOURCE_PATH/swift/cmake/caches/Runtime-WASI-wasm32.cmake" \
    -D CMAKE_TOOLCHAIN_FILE="$TOOLS_BUILD_PATH/toolchain-wasi.cmake" \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_C_COMPILER_LAUNCHER="$(which sccache)" \
    -D CMAKE_CXX_COMPILER_LAUNCHER="$(which sccache)" \
    -D CMAKE_INSTALL_PREFIX="$TARGET_TOOLCHAIN_DESTDIR/usr" \
    -D LLVM_BIN="$HOST_BUILD_DIR/llvm-$HOST_SUFFIX/bin" \
    -D LLVM_DIR="$LLVM_TARGET_BUILD_DIR/lib/cmake/llvm/" \
    -D LLVM_COMPILER_CHECKED=YES \
    -D UNIX=1 \
    -D SWIFT_NATIVE_SWIFT_TOOLS_PATH="$HOST_BUILD_DIR/swift-$HOST_SUFFIX/bin" \
    -D SWIFT_NATIVE_CLANG_TOOLS_PATH="$HOST_BUILD_DIR/llvm-$HOST_SUFFIX/bin" \
    -D SWIFT_NATIVE_LLVM_TOOLS_PATH="$HOST_BUILD_DIR/llvm-$HOST_SUFFIX/bin" \
    -D SWIFT_LIT_TEST_PATHS="$SWIFT_STDLIB_BUILD_DIR/test-wasi-wasm32/stdlib;$SWIFT_STDLIB_BUILD_DIR/test-wasi-wasm32/Concurrency/Runtime" \
    -D SWIFT_DRIVER_TEST_OPTIONS=" -Xclang-linker -resource-dir -Xclang-linker $COMPILER_RT_BUILD_DIR" \
    -D SWIFT_WASI_SYSROOT_PATH="$WASI_SYSROOT_PATH" \
    -D SWIFT_WASI_wasm32_ICU_UC_INCLUDE="$BUILD_SDK_PATH/icu/include" \
    -D SWIFT_WASI_wasm32_ICU_UC="$BUILD_SDK_PATH/icu/lib/libicuuc.a" \
    -D SWIFT_WASI_wasm32_ICU_I18N_INCLUDE="$BUILD_SDK_PATH/icu/include" \
    -D SWIFT_WASI_wasm32_ICU_I18N="$BUILD_SDK_PATH/icu/lib/libicui18n.a" \
    -D SWIFT_WASI_wasm32_ICU_DATA="$BUILD_SDK_PATH/icu/lib/libicudata.a" \
    -D SWIFT_ENABLE_EXPERIMENTAL_DIFFERENTIABLE_PROGRAMMING=YES \
    -D SWIFT_ENABLE_EXPERIMENTAL_DISTRIBUTED=YES \
    -D SWIFT_ENABLE_EXPERIMENTAL_STRING_PROCESSING=YES \
    -D SWIFT_ENABLE_EXPERIMENTAL_REFLECTION=YES \
    -D SWIFT_PATH_TO_SWIFT_SYNTAX_SOURCE="$SOURCE_PATH/swift-syntax" \
    -D SWIFT_PATH_TO_STRING_PROCESSING_SOURCE="$SOURCE_PATH/swift-experimental-string-processing" \
    -G Ninja \
    -S "$SOURCE_PATH/swift"

  # FIXME(katei): 'sdk-overlay' is explicitly used to build libcxxshim.modulemap
  # which is used only in tests, so 'ninja install' doesn't build it
  # the header and modulemap custom targets should be added as dependency of install
  ninja sdk-overlay install -C "$SWIFT_STDLIB_BUILD_DIR"

  # Link compiler-rt libs to stdlib build dir
  mkdir -p "$SWIFT_STDLIB_BUILD_DIR/lib/clang/10.0.0/"
  ln -fs "$COMPILER_RT_BUILD_DIR/lib" "$SWIFT_STDLIB_BUILD_DIR/lib/clang/10.0.0/lib"

  # Remove host CoreFoundation module directory to avoid module conflict
  # while building Foundation
  rm -rf "$TARGET_TOOLCHAIN_DESTDIR/usr/lib/swift_static/CoreFoundation"
  "$TOOLS_BUILD_PATH/build-foundation.sh" "$TARGET_TOOLCHAIN_DESTDIR" "$WASI_SYSROOT_PATH"
  "$TOOLS_BUILD_PATH/build-xctest.sh" "$TARGET_TOOLCHAIN_DESTDIR" "$WASI_SYSROOT_PATH"

}

embed_wasi_sysroot() {
  # Merge wasi-sdk and the toolchain
  cp -r "$WASI_SYSROOT_PATH" "$TARGET_TOOLCHAIN_DESTDIR/usr/share"
}

swift_version() {
  cat "$SOURCE_PATH/swift/CMakeLists.txt" | grep 'set(SWIFT_VERSION ' | sed -E 's/set\(SWIFT_VERSION "(.+)"\)/\1/'
}

create_darwin_info_plist() {
  echo "-- Create Info.plist --"
  PLISTBUDDY_BIN="/usr/libexec/PlistBuddy"

  BUNDLE_PREFIX="org.swiftwasm"
  DARWIN_TOOLCHAIN_DISPLAY_NAME_SHORT="Swift for WebAssembly Snapshot"

  if [ ${OPTIONS_DAILY_SNAPSHOT} -eq 1 ]; then
    DARWIN_TOOLCHAIN_VERSION="$(swift_version).${YEAR}${MONTH}${DAY}"
    DARWIN_TOOLCHAIN_BUNDLE_IDENTIFIER="${BUNDLE_PREFIX}.${YEAR}${MONTH}${DAY}"
    DARWIN_TOOLCHAIN_DISPLAY_NAME="${DARWIN_TOOLCHAIN_DISPLAY_NAME_SHORT} ${YEAR}-${MONTH}-${DAY}"
  else
    DARWIN_TOOLCHAIN_VERSION="$(swift_version).9999"
    DARWIN_TOOLCHAIN_BUNDLE_IDENTIFIER="${BUNDLE_PREFIX}.dev"
    DARWIN_TOOLCHAIN_DISPLAY_NAME="${DARWIN_TOOLCHAIN_DISPLAY_NAME_SHORT} Development"
  fi
  DARWIN_TOOLCHAIN_ALIAS="swiftwasm"

  DARWIN_TOOLCHAIN_INFO_PLIST="${TARGET_TOOLCHAIN_DESTDIR}/Info.plist"
  DARWIN_TOOLCHAIN_REPORT_URL="https://github.com/swiftwasm/swift/issues"
  COMPATIBILITY_VERSION=2
  COMPATIBILITY_VERSION_DISPLAY_STRING="Xcode 8.0"
  DARWIN_TOOLCHAIN_CREATED_DATE="$(date -u +'%a %b %d %T GMT %Y')"
  SWIFT_USE_DEVELOPMENT_TOOLCHAIN_RUNTIME="YES"

  rm -f "${DARWIN_TOOLCHAIN_INFO_PLIST}"

  ${PLISTBUDDY_BIN} -c "Add DisplayName string '${DARWIN_TOOLCHAIN_DISPLAY_NAME}'" "${DARWIN_TOOLCHAIN_INFO_PLIST}"
  ${PLISTBUDDY_BIN} -c "Add ShortDisplayName string '${DARWIN_TOOLCHAIN_DISPLAY_NAME_SHORT}'" "${DARWIN_TOOLCHAIN_INFO_PLIST}"
  ${PLISTBUDDY_BIN} -c "Add CreatedDate date '${DARWIN_TOOLCHAIN_CREATED_DATE}'" "${DARWIN_TOOLCHAIN_INFO_PLIST}"
  ${PLISTBUDDY_BIN} -c "Add CompatibilityVersion integer ${COMPATIBILITY_VERSION}" "${DARWIN_TOOLCHAIN_INFO_PLIST}"
  ${PLISTBUDDY_BIN} -c "Add CompatibilityVersionDisplayString string ${COMPATIBILITY_VERSION_DISPLAY_STRING}" "${DARWIN_TOOLCHAIN_INFO_PLIST}"
  ${PLISTBUDDY_BIN} -c "Add Version string '${DARWIN_TOOLCHAIN_VERSION}'" "${DARWIN_TOOLCHAIN_INFO_PLIST}"
  ${PLISTBUDDY_BIN} -c "Add CFBundleIdentifier string '${DARWIN_TOOLCHAIN_BUNDLE_IDENTIFIER}'" "${DARWIN_TOOLCHAIN_INFO_PLIST}"
  ${PLISTBUDDY_BIN} -c "Add ReportProblemURL string '${DARWIN_TOOLCHAIN_REPORT_URL}'" "${DARWIN_TOOLCHAIN_INFO_PLIST}"
  ${PLISTBUDDY_BIN} -c "Add Aliases array" "${DARWIN_TOOLCHAIN_INFO_PLIST}"
  ${PLISTBUDDY_BIN} -c "Add Aliases:0 string '${DARWIN_TOOLCHAIN_ALIAS}'" "${DARWIN_TOOLCHAIN_INFO_PLIST}"
  ${PLISTBUDDY_BIN} -c "Add OverrideBuildSettings dict" "${DARWIN_TOOLCHAIN_INFO_PLIST}"
  ${PLISTBUDDY_BIN} -c "Add OverrideBuildSettings:ENABLE_BITCODE string 'NO'" "${DARWIN_TOOLCHAIN_INFO_PLIST}"
  ${PLISTBUDDY_BIN} -c "Add OverrideBuildSettings:SWIFT_DISABLE_REQUIRED_ARCLITE string 'YES'" "${DARWIN_TOOLCHAIN_INFO_PLIST}"
  ${PLISTBUDDY_BIN} -c "Add OverrideBuildSettings:SWIFT_LINK_OBJC_RUNTIME string 'YES'" "${DARWIN_TOOLCHAIN_INFO_PLIST}"
  ${PLISTBUDDY_BIN} -c "Add OverrideBuildSettings:SWIFT_DEVELOPMENT_TOOLCHAIN string 'YES'" "${DARWIN_TOOLCHAIN_INFO_PLIST}"
  ${PLISTBUDDY_BIN} -c "Add OverrideBuildSettings:SWIFT_USE_DEVELOPMENT_TOOLCHAIN_RUNTIME string '${SWIFT_USE_DEVELOPMENT_TOOLCHAIN_RUNTIME}'" "${DARWIN_TOOLCHAIN_INFO_PLIST}"

  chmod a+r "${DARWIN_TOOLCHAIN_INFO_PLIST}"
}

show_sccache_stats() {
  # If sccache is installed in PATH
  if command -v sccache &> /dev/null; then
    sccache --show-stats
  else
    echo "sccache is not installed in PATH"
  fi
}

if [ ${OPTIONS_BUILD_HOST_TOOLCHAIN} -eq 1 ]; then
  build_host_toolchain
  echo "=================================="
  echo "Host toolchain built successfully!"
  echo "=================================="
  echo ""
  echo "sccache stats:"
  show_sccache_stats
  rm -rf "$TARGET_TOOLCHAIN_DESTDIR"
  mkdir -p "$TARGET_TOOLCHAIN_DESTDIR"
  rsync -a "$HOST_TOOLCHAIN_DESTDIR/" "$TARGET_TOOLCHAIN_DESTDIR"
fi

build_target_toolchain
echo "===================================="
echo "Target toolchain built successfully!"
echo "===================================="
echo ""
echo "sccache stats:"
show_sccache_stats
