// RUN: %{swiftc} -target wasm32-unknown-wasi -static-stdlib -sdk %{package_path}/usr/share/wasi-sysroot %s -o %t.wasm
// RUN: %{wasm_run} %t.wasm
print("Hello")
