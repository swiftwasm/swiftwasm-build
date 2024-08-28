// RUN: %{target_simple_swift_build}
// RUN: %{wasm_run} --dir %t.dir::/tmp %t.dir/.build/debug/Check.wasm | %{FileCheck} %s
// REQUIRES: FileCheck && scheme=main

import Foundation

// CHECK: processName: Check.wasm
print("processName: " + ProcessInfo.processInfo.processName)

// CHECK: hostname: localhost
print("hostname: " + ProcessInfo.processInfo.hostName)
