// RUN: rm -rf %t.dir
// RUN: mkdir -p %t.dir
// RUN: %{swiftc} -target wasm32-wasi -o %t.dir/check.wasm %s -resource-dir %{package_path}/usr/lib/swift_static -sdk %{package_path}/usr/share/wasi-sysroot
// RUN: %{wasm_run} --dir %t.dir::/tmp %t.dir/check.wasm | FileCheck %s

import Foundation

// CHECK: processName: check.wasm
print("processName: " + ProcessInfo.processInfo.processName)

// CHECK: hostname: localhost
print("hostname: " + ProcessInfo.processInfo.hostName)
