/// The digits gathered while a modifier is held, before the release
/// turns them into one row number.
///
/// A value with no behavior beyond holding and reading: the key layer
/// owns one and answers each press through it. Digits arrive one at a
/// time and read as one decimal number, so pressing 3 then 4 means 34.
/// Waiting plays no part; only consecutive digit presses count, and
/// anything else hands the input back empty.
struct NumberInput: Equatable, Sendable {

  // MARK: Internal

  /// The most digits one number holds. Rows number in the dozens, so
  /// three digits leave room while keeping a stuck key from growing
  /// the number without bound.
  static let maximumDigits = 3

  /// Whether any digit has arrived since the last reset.
  var isEmpty: Bool {
    digits.isEmpty
  }

  /// The gathered digits as one decimal number, or nothing when no
  /// number was gathered or the digits read as zero. Row numbers start
  /// at one, so zero alone is not a number.
  var number: Int? {
    guard let value = Int(digits), value > 0 else { return nil }
    return value
  }

  /// Adds one digit, dropping it when the number is already full.
  mutating func append(_ digit: Int) {
    guard (0 ... 9).contains(digit), digits.count < Self.maximumDigits else { return }
    digits.append(String(digit))
  }

  /// Forgets every gathered digit.
  mutating func reset() {
    digits = ""
  }

  // MARK: Private

  private var digits = ""

}
