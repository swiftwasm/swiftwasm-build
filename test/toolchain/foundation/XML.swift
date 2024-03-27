// RUN: rm -rf %t.dir
// RUN: mkdir -p %t.dir
// RUN: %{swiftc} -target wasm32-wasi -o %t.dir/check.wasm %s -resource-dir %{package_path}/usr/lib/swift_static -sdk %{package_path}/usr/share/wasi-sysroot
// RUN: %{wasm_run} %t.dir/check.wasm | %{FileCheck} %s
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
