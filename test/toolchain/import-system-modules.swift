// RUN: %{swiftc} -resource-dir %{package_path}/usr/lib/swift_static -target wasm32-wasi %S/Inputs/imports.swift -sdk %{package_path}/usr/share/wasi-sysroot -static-stdlib -o %t.wasm
// RUN: %{wasm_run} %t.wasm
