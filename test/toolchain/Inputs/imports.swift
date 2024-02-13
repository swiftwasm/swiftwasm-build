import Foundation
import XCTest
import WASILibc

// FIXME: This should be supported on swiftwasm branch
// #if canImport(FoundationXML)
//   #error("FoundationXML should not be able to import now")
// #endif
// 
// #if canImport(FoundationNetworking)
//   #error("FoundationNetworking should not be able to import now")
// #endif

public func main() {
  _ = Date()
  _ = UUID()
  _ = URL(string: "https://example.com")!
}
