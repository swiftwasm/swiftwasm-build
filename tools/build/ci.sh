#!/bin/bash

set -ex

SOURCE_PATH="$(cd "$(dirname $0)/../../.." && pwd)"
TOOLS_BUILD_PATH="$(cd "$(dirname "$0")" && pwd)"
SCHEME="${1:?"scheme is not specified"}"

export SCCACHE_CACHE_SIZE="50G"
export SCCACHE_DIR="$SOURCE_PATH/build-cache"

SCCACHE_INSTALL_PATH="$SOURCE_PATH/build-sdk/sccache"

install_sccache_if_needed() {
  local version="v0.6.0"
  local url="https://github.com/mozilla/sccache/releases/download/${version}/sccache-${version}-aarch64-apple-darwin.tar.gz"

  if [ -e "$SCCACHE_INSTALL_PATH" ]; then
    return
  fi

  # WORKAROUND: It seems that sccache v0.7.4 mis-reuses compilation results during cmark build
  # only on Apple Silicon. So we use older version for now.
  if [ "$(uname)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
    return
  fi

  mkdir -p "$SCCACHE_INSTALL_PATH"

  (cd "$SCCACHE_INSTALL_PATH" && curl -L "$url" | tar xz --strip-components=1)

}

install_sccache_if_needed
export PATH="$SCCACHE_INSTALL_PATH:$PATH"

$TOOLS_BUILD_PATH/build-toolchain.sh "$SCHEME"
$TOOLS_BUILD_PATH/package-toolchain --scheme "$SCHEME" --daily-snapshot
