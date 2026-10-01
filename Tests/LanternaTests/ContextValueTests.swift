import Foundation
@testable import Lanterna
import Testing

/// The JSON a context and a message are written as, read back by the
/// standard parser.
struct ContextValueTests {
  @Test(arguments: [
    "plain",
    "say \"hi\"",
    "back\\slash",
    "line\nbreak\r\ttab",
    "bell\u{07} and nul\u{00}",
    "unicode — 日本語 🌐",
    "slash / stays",
  ])
  func aStringReadsBackAsWritten(text: String) throws {
    let literal = ContextValue.jsonString(text)
    let parsed = try JSONSerialization.jsonObject(with: Data("[\(literal)]".utf8)) as? [String]
    #expect(parsed == [text])
  }

  @Test
  func controlCharactersAreEscapedAndSlashesAreNot() {
    #expect(ContextValue.jsonString("a/b\u{01}") == #""a/b\u0001""#)
  }

  @Test
  func valuesKeepTheirJSONTypes() {
    let object = ContextValue.jsonObject([
      "s": .string("x"),
      "i": .int(-3),
      "d": .double(1.5),
      "b": .bool(true),
      "n": .double(.nan),
    ])
    #expect(object == #"{"b":true,"d":1.5,"i":-3,"n":"nan","s":"x"}"#)
  }
}
