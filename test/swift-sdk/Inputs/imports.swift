import Foundation
import XCTest
import WASILibc

#if canImport(FoundationXML)
  import FoundationXML
#endif
// FIXME: This should be supported on swiftwasm branch
// #if canImport(FoundationNetworking)
//   #error("FoundationNetworking should not be able to import now")
// #endif

public func main() {
  _ = Date()
  _ = UUID()
  _ = URL(string: "https://example.com")!
}
