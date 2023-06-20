#!/bin/bash

set -ex

SOURCE_PATH="$(cd "$(dirname $0)/../../.." && pwd)"
TOOLS_BUILD_PATH="$(cd "$(dirname $0)" && pwd)"

export SCCACHE_CACHE_SIZE="50G"
export SCCACHE_DIR="$SOURCE_PATH/build-cache"

$TOOLS_BUILD_PATH/build-toolchain.sh --daily-snapshot
