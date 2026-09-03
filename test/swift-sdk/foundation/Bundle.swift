// RUN: %{target_simple_swift_build}
// RUN: %{wasm_run} --dir %t.dir::/tmp --dir %t.dir::/tmp2 %t.dir/.build/debug/Check.wasm | %{FileCheck} %s
// REQUIRES: FileCheck && scheme=main

import Foundation

// Bundle.main is derived from the path of the executable and cwd
// CHECK: bundlePath: /tmp
chdir("/tmp")
print("bundlePath:", Bundle.main.bundlePath)

// CHECK: Bundle(path:).bundlePath: /tmp2
print("Bundle(path:).bundlePath:", Bundle(path: "/tmp2")?.bundlePath ?? "nil")
