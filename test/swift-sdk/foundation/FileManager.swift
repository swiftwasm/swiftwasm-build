// RUN: %{target_simple_swift_build}
// RUN: rm -rf %t.mnt
// RUN: mkdir -p %t.mnt
// RUN: %{wasm_run} --dir %t.mnt::/tmp --dir %S/Inputs::/Inputs %t.dir/.build/debug/Check.wasm | %{FileCheck} %s
// REQUIRES: FileCheck && scheme=main

import Foundation

// CHECK: cwd: /
print("cwd: \(FileManager.default.currentDirectoryPath)")
// CHECK: chdir: true
let chdirResult = FileManager.default.changeCurrentDirectoryPath("/tmp")
print("chdir: \(chdirResult)")
// CHECK: cwd: /tmp
print("cwd: \(FileManager.default.currentDirectoryPath)")

// CHECK: homeDirectory: nil
print("homeDirectory: \(FileManager.default.homeDirectory(forUser: "nobody")?.absoluteString ?? "nil")")

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
