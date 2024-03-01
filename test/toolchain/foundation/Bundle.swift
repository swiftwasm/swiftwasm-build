// RUN: rm -rf %t.dir
// RUN: mkdir -p %t.dir
// RUN: %{swiftc} -target wasm32-wasi -o %t.dir/check.wasm %s -resource-dir %{package_path}/usr/lib/swift_static -sdk %{package_path}/usr/share/wasi-sysroot
// RUN: %{wasm_run} --dir %t.dir::/tmp --dir %t.dir::/tmp2 %t.dir/check.wasm | %{FileCheck} %s

import Foundation

// Bundle.main is derived from the path of the executable and cwd
// CHECK: bundlePath: /tmp
chdir("/tmp")
print("bundlePath:", Bundle.main.bundlePath)

// CHECK: Bundle(path:).bundlePath: /tmp2
print("Bundle(path:).bundlePath:", Bundle(path: "/tmp2")?.bundlePath ?? "nil")
