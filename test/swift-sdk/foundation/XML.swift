// RUN: %{target_simple_swift_build}
// RUN: %{wasm_run} %t.dir/.build/debug/Check.wasm | %{FileCheck} %s
// REQUIRES: FileCheck

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
