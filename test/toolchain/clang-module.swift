// RUN: rm -rf %t.dir
// RUN: mkdir -p %t.dir
// RUN: %{swift} build --package-path %S/Inputs/clang-module-example --scratch-path %t.dir --triple wasm32-unknown-wasi --static-swift-stdlib

// Skipping this test on main until we include swift-testing in the SDK
// REQUIRES: GH-5587
