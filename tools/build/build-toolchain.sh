#!/bin/bash

set -eux -o pipefail

REPO_PATH="$(cd "$(dirname $0)/../.." && pwd)"
SOURCE_PATH="$REPO_PATH/.."
SCHEME="${1:?"scheme is not specified"}"

TOOLS_BUILD_PATH="$(cd "$(dirname "$0")" && pwd)"

BUILD_DIR="$SOURCE_PATH/build"
PACKAGING_DIR="$BUILD_DIR/Packaging"

need_build_cross_compiler() {
  # If the scheme does not have any compiler patches,
  # we can skip building compiler and use the prebuilt one.
  # Return 0 if we need to build compiler, 1 otherwise.

  local patch_dir="$REPO_PATH/schemes/$SCHEME/swift"

  if [ ! -d "$patch_dir" ]; then
    return 1
  fi

  if [ -z "$(ls -A "$patch_dir")" ]; then
    return 1
  fi

  python3 -c 'import sys, json; exit(0 if json.load(sys.stdin).get("build-compiler", True) else 1)' < $REPO_PATH/schemes/$SCHEME/manifest.json
}


if need_build_cross_compiler; then
  echo "Building cross compiler..."
  "$TOOLS_BUILD_PATH/build-host-toolchain.sh"
  CROSS_COMPILER_DESTDIR=$PACKAGING_DIR/host-toolchain
else
  echo "Using prebuilt cross compiler..."
  "$TOOLS_BUILD_PATH/install-base-toolchain" --scheme "$SCHEME"
  CROSS_COMPILER_DESTDIR=$PACKAGING_DIR/base-snapshot
fi
"$TOOLS_BUILD_PATH/build-llvm-tools" --toolchain "$CROSS_COMPILER_DESTDIR"

"$TOOLS_BUILD_PATH/build-target-toolchain.sh" \
  --llvm-bin "$BUILD_DIR/llvm-tools/bin" \
  --clang-bin "$CROSS_COMPILER_DESTDIR/usr/bin" \
  --swift-bin "$CROSS_COMPILER_DESTDIR/usr/bin"

