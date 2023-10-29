#!/bin/bash

set -ex

SOURCE_PATH="$(cd "$(dirname $0)/../../.." && pwd)"
TOOLS_BUILD_PATH="$(cd "$(dirname "$0")" && pwd)"
SCHEME="${1:?"scheme is not specified"}"

export SCCACHE_CACHE_SIZE="50G"
export SCCACHE_DIR="$SOURCE_PATH/build-cache"

$TOOLS_BUILD_PATH/build-toolchain.sh "$SCHEME"
$TOOLS_BUILD_PATH/package-toolchain --scheme "$SCHEME" --daily-snapshot
