// RUN: rm -rf %t.dir
// RUN: mkdir -p %t.dir
// RUN: %{swift} build --package-path %S/Inputs/clang-module-example --scratch-path %t.dir --triple wasm32-unknown-wasi --static-swift-stdlib
