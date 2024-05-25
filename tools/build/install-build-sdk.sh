#!/bin/bash

set -eux

SOURCE_PATH="$( cd "$(dirname "$0")/../../../" && pwd  )"
TOOLS_BUILD_PATH="$(cd "$(dirname "$0")" && pwd)"
BUILD_SDK_PATH="$SOURCE_PATH/build-sdk"
SCHEME="${1:?"scheme is not specified"}"
SCHEME_DIR="$(cd "$(dirname "$0")/../../schemes/$SCHEME" && pwd)"
CURRENT_SCHEME_FILE="$BUILD_SDK_PATH/scheme"

install_libxml2() {
  read -r -a LIBXML2_URLS <<< "$(python3 -c 'import sys, json; print(" ".join(json.load(sys.stdin)["libxml2"]))' < "$SCHEME_DIR/manifest.json")"
  for url in "${LIBXML2_URLS[@]}"; do
    curl -L "$url" | tar xz -C "$BUILD_SDK_PATH"
  done
  # For backward compatibility
  if [ "$SCHEME" = "release-5.9" ] || [ "$SCHEME" = "release-5.10" ] || [ "$SCHEME" = "release-6.0" ]; then
    ln -sf libxml2-wasm32-unknown-wasi "$BUILD_SDK_PATH/libxml2"
  fi
}

install_icu() {
  read -r -a ICU_URLS <<< "$(python3 -c 'import sys, json; print(" ".join(json.load(sys.stdin)["icu4c"]))' < "$SCHEME_DIR/manifest.json")"
  rm -rf "$BUILD_SDK_PATH/icu"
  for url in "${ICU_URLS[@]}"; do
    curl -L "$url" | tar Jx -C "$BUILD_SDK_PATH"
  done
  # Just for backward compatibility
  if [ -d "$BUILD_SDK_PATH/icu_out" ]; then
    mv $BUILD_SDK_PATH/icu_out "$BUILD_SDK_PATH/icu"
  fi
}

install_wasi-sysroot() {
  
  local WASI_SYSROOT_URL
  WASI_SYSROOT_URL="$(python3 -c 'import sys, json; print(json.load(sys.stdin).get("wasi-sysroot", ""))' < "$SCHEME_DIR/manifest.json")"
  if [ -z "$WASI_SYSROOT_URL" ]; then
    echo "wasi-sysroot is not specified in the manifest.json. Skip installing wasi-sysroot."
    return
  fi

  curl -L "$WASI_SYSROOT_URL" | tar xz

  mv "wasi-sysroot" "$BUILD_SDK_PATH/wasi-sysroot"
  if [ -d "$SCHEME_DIR/wasi-sysroot" ]; then
    patch -p1 -d "$BUILD_SDK_PATH/wasi-sysroot" < "$SCHEME_DIR/wasi-sysroot"/*.patch
  fi
}

should_clean_install_sdk() {
  # Clean sdk directory if the existing one is not compatible with the current scheme
  # Return 0 if the sdk directory should be cleaned
  if [ ! -e "$CURRENT_SCHEME_FILE" ]; then
    return 0
  fi
  local current_scheme
  current_scheme="$(cat "$CURRENT_SCHEME_FILE")"

  if [ "$current_scheme" != "$SCHEME" ]; then
    return 0
  fi

  return 1
}

workdir=$(mktemp -d)
pushd "$workdir"

if should_clean_install_sdk; then
  rm -rf "$BUILD_SDK_PATH"
fi

mkdir -p "$BUILD_SDK_PATH"
echo "$SCHEME" > "$BUILD_SDK_PATH/scheme"

if [ ! -e "$BUILD_SDK_PATH/libxml2" ]; then
  install_libxml2
fi

if [ ! -e "$BUILD_SDK_PATH/icu" ]; then
  install_icu
fi

if [ ! -e "$BUILD_SDK_PATH/wasi-sysroot" ]; then
  install_wasi-sysroot
fi
