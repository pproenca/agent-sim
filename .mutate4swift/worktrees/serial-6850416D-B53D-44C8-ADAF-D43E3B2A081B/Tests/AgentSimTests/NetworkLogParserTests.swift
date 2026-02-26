import Testing
@testable import AgentSimLib

@Suite("NetworkLogParser — HTTP log parsing")
struct NetworkLogParserTests {

  @Test("Empty input returns empty result with diagnosticsEnabled=false")
  func emptyInput() {
    let result = NetworkLogParser.parse("")

    #expect(result.diagnosticsEnabled == false)
    #expect(result.requests.isEmpty)
    #expect(result.rawEntries.isEmpty)
  }

  @Test("Non-CFNetwork log entries appear as raw entries")
  func nonCFNetworkEntries() {
    let ndjson = """
      {"timestamp":"2026-02-21 13:33:43.175745+0000","subsystem":"com.maddie.app","eventMessage":"User signed in"}
      """

    let result = NetworkLogParser.parse(ndjson)

    #expect(result.diagnosticsEnabled == false)
    #expect(result.rawEntries.count == 1)
    #expect(result.rawEntries[0].message == "User signed in")
  }

  @Test("Parses HTTP status 200 response")
  func parsesStatus200() {
    let ndjson = cfnetworkEntry(
      taskID: "D2686A70-AD68-4B9E-9500-A74972B1EB1F",
      message: "Task <D2686A70-AD68-4B9E-9500-A74972B1EB1F>.<1> received response, status 200"
    )

    let result = NetworkLogParser.parse(ndjson)

    #expect(result.diagnosticsEnabled == true)
    #expect(result.requests.count == 1)
    #expect(result.requests[0].statusCode == 200)
    #expect(result.requests[0].isError == false)
  }

  @Test("Parses HTTP status 401 as error")
  func parsesStatus401() {
    let ndjson = cfnetworkEntry(
      taskID: "AAAA-BBBB",
      message: "Task <AAAA-BBBB>.<1> received response, status 401"
    )

    let result = NetworkLogParser.parse(ndjson)

    #expect(result.requests.count == 1)
    #expect(result.requests[0].statusCode == 401)
    #expect(result.requests[0].isError == true)
  }

  @Test("Parses NSURLError code from error message")
  func parsesErrorCode() {
    let ndjson = cfnetworkEntry(
      taskID: "CCCC-DDDD",
      message: "Task <CCCC-DDDD>.<1> finished with error [-999] Error Domain=NSURLErrorDomain Code=-999"
    )

    let result = NetworkLogParser.parse(ndjson)

    #expect(result.requests.count == 1)
    #expect(result.requests[0].isError == true)
    #expect(result.requests[0].errorDetail == "NSURLError -999")
  }

  @Test("Extracts method and URL from request line")
  func parsesMethodAndURL() {
    let ndjson = cfnetworkEntry(
      taskID: "EEEE-FFFF",
      message: "Task <EEEE-FFFF>.<1> GET https://api.example.com/v1/sessions received response, status 200"
    )

    let result = NetworkLogParser.parse(ndjson)

    #expect(result.requests.count == 1)
    #expect(result.requests[0].method == "GET")
    #expect(result.requests[0].url == "https://api.example.com/v1/sessions")
  }

  @Test("Extracts duration from summary line")
  func parsesDuration() {
    let entry1 = cfnetworkEntry(
      taskID: "1111-2222",
      message: "Task <1111-2222>.<1> received response, status 200"
    )
    let entry2 = cfnetworkEntry(
      taskID: "1111-2222",
      message: "Task <1111-2222>.<1> summary for task success {transaction_duration_ms=149, response_status=200}"
    )

    let result = NetworkLogParser.parse(entry1 + "\n" + entry2)

    #expect(result.requests.count == 1)
    #expect(result.requests[0].durationMs == 149)
  }

  @Test("formatTimestamp extracts HH:mm:ss from full timestamp")
  func formatsTimestamp() {
    let ndjson = """
      {"timestamp":"2026-02-21 13:33:43.175745+0000","subsystem":"com.apple.CFNetwork","eventMessage":"Task <AAAA-BBBB>.<1> received response, status 200"}
      """

    let result = NetworkLogParser.parse(ndjson)

    #expect(result.requests[0].timestamp == "13:33:43")
  }

  @Test("Correlates multiple entries for the same task")
  func correlatesEntries() {
    // Task IDs must be hex UUID format to match the regex
    let uuid = "D2686A70-AD68-4B9E-9500-A74972B1EB1F"
    let entry1 = cfnetworkEntry(
      taskID: uuid,
      message: "Task <\(uuid)>.<1> GET https://api.example.com/v1/data received response, status 200",
      timestamp: "2026-02-21 10:00:00.000+0000"
    )
    let entry2 = cfnetworkEntry(
      taskID: uuid,
      message: "Task <\(uuid)>.<1> summary for task success {transaction_duration_ms=250, response_status=200}",
      timestamp: "2026-02-21 10:00:00.250+0000"
    )

    let result = NetworkLogParser.parse(entry1 + "\n" + entry2)

    #expect(result.requests.count == 1) // merged into one request
    #expect(result.requests[0].statusCode == 200)
    #expect(result.requests[0].method == "GET")
    #expect(result.requests[0].durationMs == 250)
  }

  // MARK: - Helpers

  private func cfnetworkEntry(
    taskID: String,
    message: String,
    timestamp: String = "2026-02-21 13:33:43.175745+0000"
  ) -> String {
    """
    {"timestamp":"\(timestamp)","subsystem":"com.apple.CFNetwork","eventMessage":"\(message)"}
    """
  }
}
