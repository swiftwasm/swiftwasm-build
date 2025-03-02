#!/bin/bash

set -eux -o pipefail

REPO_PATH="$(cd "$(dirname $0)/../.." && pwd)"
SOURCE_PATH="$REPO_PATH/.."
SCHEME="${1:?"scheme is not specified"}"

TOOLS_BUILD_PATH="$(cd "$(dirname "$0")" && pwd)"

BUILD_DIR="$SOURCE_PATH/build"
PACKAGING_DIR="$BUILD_DIR/Packaging"
CROSS_COMPILER_DESTDIR=$PACKAGING_DIR/base-snapshot

"$TOOLS_BUILD_PATH/install-base-toolchain" --scheme "$SCHEME"
"$TOOLS_BUILD_PATH/build-llvm-tools" --toolchain "$CROSS_COMPILER_DESTDIR"

"$REPO_PATH/schemes/$SCHEME/build/build-target-toolchain.sh" \
  --llvm-bin "$BUILD_DIR/llvm-tools/bin" \
  --clang-bin "$CROSS_COMPILER_DESTDIR/usr/bin" \
  --swift-bin "$CROSS_COMPILER_DESTDIR/usr/bin" \
  --scheme "$SCHEME"

