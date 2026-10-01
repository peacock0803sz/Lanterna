@testable import Lanterna
import Testing

/// The compact syntax and the statement gate, pinned before the
/// views lean on them. A change in what a row means must show up
/// here rather than slipping past silently.
struct LogQueryTests {
  @Test
  func bareWordsSearchTheMessage() {
    let parsed = LightweightFilter.parse("AX")
    #expect(parsed.conditions.count == 1)
    #expect(parsed.conditions[0].fragment == "instr(message, ?) > 0")
    #expect(parsed.conditions[0].values == [.text("AX")])
    #expect(parsed.conditions[0].chip == "Message contains AX")
  }

  @Test
  func quotedPhrasesStayWhole() {
    let parsed = LightweightFilter.parse("\"AX title\"")
    #expect(parsed.conditions.count == 1)
    #expect(parsed.conditions[0].values == [.text("AX title")])
  }

  @Test
  func levelRangeComparesInSeverityOrder() {
    let parsed = LightweightFilter.parse("level>=warn")
    #expect(parsed.conditions.count == 1)
    #expect(parsed.conditions[0].fragment == "level IN (?, ?)")
    #expect(parsed.conditions[0].values == [.text("warning"), .text("error")])
  }

  @Test
  func unknownLevelMatchesNothing() {
    let parsed = LightweightFilter.parse("level>=strange")
    #expect(parsed.conditions.count == 1)
    #expect(parsed.conditions[0].fragment == "1 = 0")
  }

  @Test
  func nestedPathsReadThePayload() {
    let parsed = LightweightFilter.parse("app.bundle=com.example")
    #expect(parsed.conditions[0].fragment == "json_extract_string(payload, '$.app.bundle') = ?")
    #expect(parsed.conditions[0].values == [.text("com.example")])
  }

  @Test
  func arrayPathsMatchAnyElement() {
    let parsed = LightweightFilter.parse("attempts[].result=failed")
    #expect(parsed.conditions[0].fragment.contains("[*]"))
    #expect(parsed.conditions[0].values == [.text("\"failed\"")])
  }

  @Test
  func timeBoundsBecomeMillsComparisons() {
    let parsed = LightweightFilter.parse("after:2026-01-02")
    #expect(parsed.conditions.count == 1)
    #expect(parsed.conditions[0].fragment == "ts_ms >= ?")
    guard case .integer(let mills) = parsed.conditions[0].values.first else {
      Issue.record("time bound should bind an integer")
      return
    }
    #expect(mills > 1_700_000_000_000)
  }

  @Test
  func removingAChipDropsItsSourceToken() {
    let parsed = LightweightFilter.parse("level>=warn category:ax")
    #expect(parsed.removingChip("Level: warning, error") == "category:ax")
    #expect(parsed.removingChip("No such chip") == "level>=warn category:ax")
  }

  @Test
  func emptyRowsMatchAll() {
    #expect(LightweightFilter.parse("").predicate == "1 = 1")
    #expect(LightweightFilter.parse("   ").predicate == "1 = 1")
  }

  @Test
  func plainReadsPassWithAFilledCap() {
    let verdict = DatabaseStatementCheck.check(
      "SELECT seq FROM entries WHERE ts_ms >= 0"
    )
    #expect(verdict.allowed)
    #expect(verdict.refusal == nil)
    #expect(verdict.effectiveText.hasSuffix("LIMIT 5000"))
  }

  @Test
  func existingCapsStayUntouched() {
    let verdict = DatabaseStatementCheck.check(
      "SELECT seq FROM entries WHERE ts_ms >= 0 LIMIT 10"
    )
    #expect(verdict.allowed)
    #expect(verdict.effectiveText.hasSuffix("LIMIT 10"))
  }

  @Test
  func writesAreRefused() {
    for statement in [
      "DELETE FROM entries WHERE ts_ms >= 0",
      "DROP TABLE entries",
      "SELECT seq FROM entries WHERE ts_ms >= 0; DELETE FROM entries",
    ] {
      let verdict = DatabaseStatementCheck.check(statement)
      #expect(!verdict.allowed)
      #expect(verdict.refusal == "SQL mode is read-only.")
    }
  }

  @Test
  func commentsAndQuotesNeverHideWrites() {
    for statement in [
      "SELECT * FROM entries WHERE ts_ms > 0 LIMIT 1 -- '\n) ORDER BY ts_ms) TO '/tmp/x.csv'; "
        + "DELETE FROM entries; SELECT 1 -- '",
      "/* x */ DELETE FROM entries WHERE ts_ms > 0",
      "-- x\nDROP TABLE entries",
      "WITH doomed AS (SELECT seq FROM entries) DELETE FROM entries WHERE ts_ms > 0",
      "SELECT * INTO copied FROM entries WHERE ts_ms > 0",
      "SELECT seq FROM entries WHERE ts_ms > 0 /* ' */ ; DELETE FROM entries",
      "SELECT seq FROM entries WHERE ts_ms > 0 AND message = $$'$$; DELETE FROM entries",
      "SELECT seq FROM entries WHERE ts_ms > 0 AND message = E'\\''; DELETE FROM entries",
      "SELECT seq FROM entries WHERE ts_ms > 0) TO '/tmp/x.csv' (HEADER false) --",
      "SELECT seq FROM entries WHERE ts_ms > 0 /* unterminated",
    ] {
      let verdict = DatabaseStatementCheck.check(statement)
      #expect(!verdict.allowed, "\(statement)")
    }
  }

  @Test
  func commentsAroundAReadStillPass() {
    let verdict = DatabaseStatementCheck.check(
      "-- don't\nSELECT seq FROM entries /* it's */ WHERE ts_ms >= 0; -- done"
    )
    #expect(verdict.allowed)
    #expect(!verdict.effectiveText.contains(";"))
  }

  @Test
  func quotedWordsNeverReadAsStatements() {
    let verdict = DatabaseStatementCheck.check(
      "SELECT seq FROM entries WHERE ts_ms >= 0 AND message = 'delete me'"
    )
    #expect(verdict.allowed)
  }

  @Test
  func missingTimeBoundsAreRefused() {
    let verdict = DatabaseStatementCheck.check("SELECT seq FROM entries")
    #expect(!verdict.allowed)
    #expect(verdict.refusal == "SQL needs a time bound (after/before on ts_ms).")
  }
}
