// RUN: %{swiftc} -target wasm32-wasi -o %t.wasm %s -resource-dir %{package_path}/usr/lib/swift_static -sdk %{package_path}/usr/share/wasi-sysroot
// RUN: rm -rf %t.dir
// RUN: mkdir -p %t.dir
// RUN: %{wasm_run} --dir %t.dir::/tmp --dir %S/Inputs::/Inputs %t.wasm | %{FileCheck} %s

import Foundation

// CHECK: cwd: /
print("cwd: \(FileManager.default.currentDirectoryPath)")
// CHECK: chdir: true
let chdirResult = FileManager.default.changeCurrentDirectoryPath("/tmp")
print("chdir: \(chdirResult)")
// CHECK: cwd: /tmp
print("cwd: \(FileManager.default.currentDirectoryPath)")

// CHECK: homeDirectory: nil
print("homeDirectory: \(String(describing: FileManager.default.homeDirectory(forUser: "nobody")))")

// CHECK: temporaryDirectory: file:///tmp/
print("temporaryDirectory: \(FileManager.default.temporaryDirectory)")

// CHECK: contentsOfDirectory(/Inputs): ["check.dir", "empty.txt", "hello.txt"]
print("contentsOfDirectory(/Inputs): \(try! FileManager.default.contentsOfDirectory(atPath: "/Inputs").sorted())")
// CHECK: contentsOfDirectory(/Inputs/check.dir): ["check0.txt", "check1.txt"]
print("contentsOfDirectory(/Inputs/check.dir): \(try! FileManager.default.contentsOfDirectory(atPath: "/Inputs/check.dir").sorted())")

// CHECK: Data(contentsOf: /Inputs/hello.txt): 6 bytes
print("Data(contentsOf: /Inputs/hello.txt): \(try! Data(contentsOf: URL(fileURLWithPath: "/Inputs/hello.txt")))")
// CHECK: String(contentsOf: /Inputs/hello.txt): world
print("String(contentsOf: /Inputs/hello.txt): \(try! String(contentsOf: URL(fileURLWithPath: "/Inputs/hello.txt")))")

// CHECK: mountedVolumeURLs: ["/Inputs", "/tmp"]
print("mountedVolumeURLs: \(FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys:[], options: [])?.map { $0.path }.sorted() ?? [])")
