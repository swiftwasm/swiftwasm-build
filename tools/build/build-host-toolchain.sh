#!/bin/bash

set -ex
SOURCE_PATH="$(cd "$(dirname "$0")/../../.." && pwd)"
TOOLS_BUILD_PATH="$(cd "$(dirname "$0")" && pwd)"

PACKAGING_DIR="$SOURCE_PATH/build/Packaging"
HOST_TOOLCHAIN_DESTDIR=$PACKAGING_DIR/host-toolchain

case $(uname -s) in
  Darwin)
    HOST_BUILD_PRESET=wasm_buildbot_osx_package
  ;;
  Linux)
    HOST_BUILD_PRESET=wasm_buildbot_linux
  ;;
  *)
    echo "Unrecognised platform $(uname -s)"
    exit 1
  ;;
esac

build_host_toolchain() {
  # Build the host toolchain and SDK first.
  "$SOURCE_PATH/swift/utils/build-script" \
    --preset-file="$TOOLS_BUILD_PATH/build-presets.ini" \
    --preset=$HOST_BUILD_PRESET \
    HOST_ARCHITECTURE="$(uname -m)" \
    INSTALL_DESTDIR="$HOST_TOOLCHAIN_DESTDIR"
}

show_sccache_stats() {
  # If sccache is installed in PATH
  if command -v sccache &> /dev/null; then
    sccache --show-stats
  else
    echo "sccache is not installed in PATH"
  fi
}

build_host_toolchain
echo "=================================="
echo "Host toolchain built successfully!"
echo "=================================="
echo ""
echo "sccache stats:"
show_sccache_stats
