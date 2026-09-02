// RUN: %{target_simple_swift_build}
// RUN: %{wasm_run} %t.dir/.build/debug/Check.wasm | %{FileCheck} %s
// REQUIRES: FileCheck
// The hermetic full-LTO flavour compiles every module with
// `-experimental-hermetic-seal-at-link`, which makes the client dispatch
// XMLNode's open class members through a dispatch thunk. The Foundation stack is
// shipped as bitcode but *not* sealed, and it emits no dispatch thunks, so
// the link fails with `undefined symbol: $s13FoundationXML7XMLNodeC11stringValueSSSgvgTj`.
// Remove this line once Foundation itself can be sealed
// (swift-frontend asserts in typeIdForMethod today).
// UNSUPPORTED: hermetic-lto

import FoundationXML

let xml = """
<note>
  <to>Tove</to>
  <from>Jani</from>
  <heading>Reminder</heading>
  <body>Don't forget me this weekend!</body>
</note>
"""

let xmlData = xml.data(using: .utf8)!
let document = try XMLDocument(data: xmlData)

let to = try document.nodes(forXPath: "/note/to").first?.stringValue
// CHECK: to: Tove
print("to: \(to!)")
