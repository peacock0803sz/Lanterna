@testable import Lanterna
import Testing

// MARK: - NumberInputTests

/// How pressed digits gather into one row number.
///
/// Digits arrive one at a time and read as one decimal number, so 3 then
/// 4 means 34. What is settled here is that gathering, and only it —
/// which row a number names and what a release does belong to the caller.
struct NumberInputTests {

  @Test
  func emptyReadsAsNoNumber() {
    #expect(NumberInput().isEmpty)
    #expect(NumberInput().number == nil)
  }

  @Test
  func singleDigitReadsAsItself() {
    var input = NumberInput()
    input.append(3)
    #expect(!input.isEmpty)
    #expect(input.number == 3)
  }

  @Test
  func sequentialDigitsReadAsOneDecimalNumber() {
    var input = NumberInput()
    input.append(3)
    input.append(4)
    #expect(input.number == 34)
  }

  @Test
  func leadingZerosReadAsDecimal() {
    var input = NumberInput()
    input.append(0)
    input.append(7)
    #expect(input.number == 7)
  }

  @Test
  func loneZeroReadsAsNoNumber() {
    var input = NumberInput()
    input.append(0)
    #expect(!input.isEmpty)
    #expect(input.number == nil)
  }

  @Test
  func digitsPastThreeAreDropped() {
    var input = NumberInput()
    input.append(1)
    input.append(2)
    input.append(3)
    input.append(4)
    #expect(input.number == 123)
  }

  @Test
  func resetForgetsEveryDigit() {
    var input = NumberInput()
    input.append(3)
    input.reset()
    #expect(input.isEmpty)
    #expect(input.number == nil)
  }

}
