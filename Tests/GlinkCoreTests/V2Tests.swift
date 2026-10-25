import Foundation
import Testing
@testable import GlinkCore

/// A fake on-device model: fixed availability, streams a canned answer in two snapshots.
struct MockModel: OnDeviceModel {
    var availability: AIAvailability
    var answer = "A closure is a self-contained block of code."
    nonisolated(unsafe) static var lastPrompt = ""

    func streamResponse(instructions: String, prompt: String) -> AsyncThrowingStream<String, Error> {
        MockModel.lastPrompt = prompt
        let answer = self.answer
        return AsyncThrowingStream { c in
            c.yield(String(answer.prefix(10)))
            c.yield(answer)
            c.finish()
        }
    }
}

@Suite("On-device AI", .serialized)
struct AIEngineTests {
    func collect(_ stream: AsyncThrowingStream<String, Error>) async -> (last: String?, error: Error?) {
        var last: String?
        do { for try await s in stream { last = s } } catch { return (last, error) }
        return (last, nil)
    }

    @Test func streamsWhenAvailable() async {
        let engine = AIEngine(model: MockModel(availability: .available))
        let (last, error) = await collect(engine.stream(instruction: nil, input: "What is a closure in Swift?"))
        #expect(error == nil)
        #expect(last == "A closure is a self-contained block of code.")
    }

    @Test(arguments: [AIUnavailableReason.osTooOld, .deviceNotEligible, .appleIntelligenceOff, .modelNotReady])
    func unavailableModelFailsWithReason(reason: AIUnavailableReason) async {
        let engine = AIEngine(model: MockModel(availability: .unavailable(reason)))
        #expect(engine.availability == .unavailable(reason))
        let (last, error) = await collect(engine.stream(instruction: nil, input: "hi"))
        #expect(last == nil)
        #expect(error as? AIEngineError == .unavailable(reason))
        #expect(!reason.title.isEmpty && !reason.message.isEmpty)
    }

    @Test func settingOffWinsOverCapableModel() async {
        let engine = AIEngine(model: MockModel(availability: .available), isEnabled: { false })
        #expect(engine.availability == .unavailable(.disabledInSettings))
        let (_, error) = await collect(engine.stream(instruction: nil, input: "hi"))
        #expect(error as? AIEngineError == .unavailable(.disabledInSettings))
    }

    @Test func emptyInputIsRejected() async {
        let engine = AIEngine(model: MockModel(availability: .available))
        let (_, error) = await collect(engine.stream(instruction: nil, input: "   \n"))
        #expect(error as? AIEngineError == .emptyInput)
    }

    @Test func promptIncludesInstructionTextAndHistory() async {
        let engine = AIEngine(model: MockModel(availability: .available))
        _ = await collect(engine.stream(instruction: "Fix grammar.", input: "i has a cat",
                                        history: [AITurnText(prompt: "earlier q", response: "earlier a")]))
        #expect(MockModel.lastPrompt.contains("Fix grammar."))
        #expect(MockModel.lastPrompt.contains("<text>\ni has a cat\n</text>"))
        #expect(MockModel.lastPrompt.contains("earlier q") && MockModel.lastPrompt.contains("earlier a"))
    }

    @Test func onlyAppleIntelligenceOffPointsToSystemSettings() {
        #expect(AIUnavailableReason.appleIntelligenceOff.opensSystemSettings)
        #expect(!AIUnavailableReason.osTooOld.opensSystemSettings)
    }
}

@Suite("Undo")
struct UndoLogTests {
    @Test func newestFirstAndUndoMarksEntry() {
        var log = UndoLog<String>()
        log.record("Snap left", payload: "a")
        let id = log.record("Trash file", payload: "b")
        #expect(log.lastReversible()?.id == id)
        let first = log.markUndone(id)
        let second = log.markUndone(id)                    // can't undo twice
        #expect(first && !second)
        #expect(log.lastReversible()?.title == "Snap left")
    }

    @Test func expiredEntriesAreNotReversible() {
        var log = UndoLog<Int>()
        let t0 = Date()
        let id = log.record("Expanded ;sig", payload: 1, at: t0, expiresAfter: 30)
        #expect(log.entry(id: id)!.isReversible(at: t0.addingTimeInterval(10)))
        #expect(!log.entry(id: id)!.isReversible(at: t0.addingTimeInterval(31)))
        #expect(log.lastReversible(at: t0.addingTimeInterval(31)) == nil)
        let late = log.markUndone(id, at: t0.addingTimeInterval(31))
        #expect(!late)
    }

    @Test func keepsOnlyTheLastTwenty() {
        var log = UndoLog<Int>(capacity: 20)
        for i in 0..<25 { log.record("#\(i)", payload: i) }
        #expect(log.entries.count == 20)
        #expect(log.entries.first?.payload == 24)
        #expect(log.entries.last?.payload == 5)
    }
}
