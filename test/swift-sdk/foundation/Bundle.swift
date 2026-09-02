// RUN: %{target_simple_swift_build}
// RUN: %{wasm_run} --dir %t.dir::/tmp --dir %t.dir::/tmp2 %t.dir/.build/debug/Check.wasm | %{FileCheck} %s
// REQUIRES: FileCheck && scheme=main
// The hermetic full-LTO flavour compiles every module with
// `-experimental-hermetic-seal-at-link`, which makes the client dispatch
// Bundle's open class properties through a dispatch thunk. The Foundation stack is
// shipped as bitcode but *not* sealed, and it emits no dispatch thunks, so
// the link fails with `undefined symbol: $s10Foundation6BundleC10bundlePathSSvgTj`.
// Remove this line once Foundation itself can be sealed
// (swift-frontend asserts in typeIdForMethod today).
// UNSUPPORTED: hermetic-lto

import Foundation

// Bundle.main is derived from the path of the executable and cwd
// CHECK: bundlePath: /tmp
chdir("/tmp")
print("bundlePath:", Bundle.main.bundlePath)

// CHECK: Bundle(path:).bundlePath: /tmp2
print("Bundle(path:).bundlePath:", Bundle(path: "/tmp2")?.bundlePath ?? "nil")
