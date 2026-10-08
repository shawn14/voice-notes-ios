import Foundation
let reportPath = CommandLine.arguments[1]
let briefPath = CommandLine.arguments[2]
let report = try String(contentsOfFile: reportPath, encoding: .utf8)
let brief = try String(contentsOfFile: briefPath, encoding: .utf8)
let sourceLine = brief.components(separatedBy: "\n").first { $0.hasPrefix("Note ID: ") }!
let sourceID = UUID(uuidString: String(sourceLine.dropFirst("Note ID: ".count)))!
let draft = try AgentResultDraft(sourceID: sourceID, sourceTitle: "Standup with Lena", report: report)
precondition(draft.report == report)
precondition(draft.content.hasSuffix(report))
precondition(draft.content.contains("does not independently verify its claims or complete tasks"))
precondition(AgentResultDraft.sourceID(annotation: draft.annotation) == sourceID)
precondition(AgentResultDraft.sourceID(annotation: "Unrelated user annotation") == nil)
precondition(AgentResultDraft.sourceID(annotation: draft.annotation + "\nextra") == nil)
precondition(report.contains(sourceID.uuidString))
precondition(draft.report.contains("## Unresolved"))
precondition(draft.report.contains("Browser screenshot proof was not generated"))
for invalid in [" \n\t", String(repeating: "x", count: 100_001)] {
    do {
        _ = try AgentResultDraft(sourceID: sourceID, sourceTitle: "Source", report: invalid)
        fatalError("Invalid report accepted")
    } catch { }
}
let evidence: [String: Any] = ["passed": true, "method": "actual production helper with actual native-agent report and copied source packet", "sourceID": sourceID.uuidString, "reportCharacters": report.count, "verbatimReport": true, "sourceAnnotationRoundTrip": true, "blankAndOversizeRejected": true, "scope": "formatter only; no native UI or SwiftData persistence proof"]

precondition(AgentResultDraft.report(content: draft.content, annotation: draft.annotation) == report)
precondition(AgentResultDraft.report(content: "User edited body", annotation: draft.annotation) == nil)
precondition(AgentResultDraft.report(content: draft.content, annotation: "Unrelated annotation") == nil)

let data = try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
print(String(data: data, encoding: .utf8)!)
