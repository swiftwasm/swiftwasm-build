#!/bin/bash

set -eux

SOURCE_PATH="$( cd "$(dirname "$0")/../../../" && pwd  )"
TOOLS_BUILD_PATH="$(cd "$(dirname "$0")" && pwd)"
BUILD_SDK_PATH="$SOURCE_PATH/build-sdk"
SCHEME="${1:?"scheme is not specified"}"
SCHEME_DIR="$(cd "$(dirname "$0")/../../schemes/$SCHEME" && pwd)"

install_libxml2() {
  LIBXML2_URL="https://github.com/swiftwasm/libxml2-wasm/releases/download/1.0.0/libxml2-wasm32-unknown-wasi.tar.gz"
  curl -L "$LIBXML2_URL" | tar xz
  rm -rf "$BUILD_SDK_PATH/libxml2"
  mv libxml2-wasm32-unknown-wasi "$BUILD_SDK_PATH/libxml2"
}

install_icu() {
  local ICU_URL
  ICU_URL="$(python3 -c 'import sys, json; print(json.load(sys.stdin)["icu4c"])' < "$SCHEME_DIR/manifest.json")"
  curl -L "$ICU_URL" | tar Jx
  rm -rf "$BUILD_SDK_PATH/icu"
  if [ -d "icu_out" ]; then
    # Just for backward compatibility
    mv icu_out "$BUILD_SDK_PATH/icu"
  else
    mv icu "$BUILD_SDK_PATH/icu"
  fi
}

install_wasi-sysroot() {
  
  local WASI_SYSROOT_URL
  WASI_SYSROOT_URL="$(python3 -c 'import sys, json; print(json.load(sys.stdin)["wasi-sysroot"])' < "$SCHEME_DIR/manifest.json")"

  curl -L "$WASI_SYSROOT_URL" | tar xz

  mv "wasi-sysroot" "$BUILD_SDK_PATH/wasi-sysroot"
  if [ -d "$SCHEME_DIR/wasi-sysroot" ]; then
    patch -p1 -d "$BUILD_SDK_PATH/wasi-sysroot" < "$SCHEME_DIR/wasi-sysroot"/*.patch
  fi
}

workdir=$(mktemp -d)
pushd "$workdir"

mkdir -p "$BUILD_SDK_PATH"

if [ ! -e "$BUILD_SDK_PATH/libxml2" ]; then
  install_libxml2
fi

if [ ! -e "$BUILD_SDK_PATH/icu" ]; then
  install_icu
fi

if [ ! -e "$BUILD_SDK_PATH/wasi-sysroot" ]; then
  install_wasi-sysroot
fi
